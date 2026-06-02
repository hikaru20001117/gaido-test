# Excel テンプレート書き込み手順

## 概要

`openpyxl` を使い、`assets/risk_templete.xlsx` の「リスク管理計画シート」にリスク計画書データを書き込む。

テンプレートファイルのパス（SKILL.md と同じディレクトリからの相対パス）:
```
assets/risk_templete.xlsx
```

出力先（ターゲットリポジトリのルートからの相対パス）:
```
ai_generated/proposals/{案件名}/risk_plan/risk_plan.xlsx
```

---

## テンプレートの構造

### シート一覧

| シート名 | 役割 | 書き込み |
|---------|------|--------|
| 案件チェックリスト説明 | チェックリストの説明 | 編集禁止 |
| 案件チェックリスト | Yes/No 回答・リスク有無 | **checklist_writer.md 参照** |
| リスク管理計画立案手順ガイド | 手順ガイド | **編集禁止** |
| リスク管理計画シート | リスク計画データ | **ここに書き込む** |
| 【参考】非機能一覧(開発見積用） | 参考情報 | 編集禁止 |
| 【参考】リスク分析シート | 参考情報 | 編集禁止 |
| 【編集不可】リスク観点リスト | D列選択肢の定義 | 編集禁止 |
| 改訂履歴 | 改訂履歴 | 編集禁止 |
| 分類 | 内部分類定義 | 編集禁止 |

書き込み対象シート名: **リスク管理計画シート**

ヘッダー行: **12行目**  
記入例・説明行: 13行目（変更しない）  
データ書き込み開始行: **14行目**

### 列マッピング

| 列 | ヘッダー | 書き込む内容 | 備考 |
|----|---------|------------|------|
| A | No | 変更不要 | 1〜が既に入力済み |
| B | 記入日 | 作成日（`YYYY/MM/DD` 形式） | |
| C | リスクイベント | リスクの内容（要因 + 影響） | |
| D | リスク観点 | `【編集不可】リスク観点リスト`シートの25項目から最も近いものを選択（`references/risk_categories.md` の「D列 リスク観点」を参照） | 文字列は選択肢と完全一致させること |
| E | 確率（%） | 発生確率（**小数**、例: `0.20`）※列がパーセント書式のため整数ではなく小数で渡す | |
| F | リスクインパクト | 影響度の説明テキスト（金額算出の根拠） | |
| G | 金額（¥M） | 影響度（**百万円単位**、例: `3.0`） | |
| H | 予測値（¥M） | 期待損失額（**百万円単位**）= G × (E × 100) / 100 = G × E | |
| I | Top20 | 予測値の降順で順位付け（1〜） | |
| J | 対応方針 | 「回避」「転嫁」「軽減」「受容」のいずれか | プルダウン選択肢 |
| K | 対応策 | リスクを顕在化させないための具体的対応策 | |
| O | コンティンジェンシー予備費（¥M） | コンテ判定の場合: 予測値（H列と同値）を記入。原価判定の場合: 空欄 | |

**注意**: L〜N列（対応期限・対応責任者・完了日）、P〜V列（監視情報・顕在化対応）は記入しない（プロジェクト開始後にPMが記入する欄）。

### ヘッダー情報の書き込み

テンプレートのヘッダー部分（行3〜4）はラベルセルと結合値セルが分離している。ラベルセルは変更せず、隣の結合値セルに値のみを書き込む。

| ラベルセル（変更不要） | 値を書き込むセル | 内容 | 書き込む値 |
|---------------------|----------------|------|----------|
| C3 `顧客名／SI案件名 ：` | **D3**（D3:F3結合） | 顧客名 | `{顧客名}` |
| G3:H3 `プロジェクト名 ：` | **I3**（I3:K3結合） | プロジェクト名 | `{プロジェクト名}` |
| C4 `SI案件コード ：` | **D4**（D4:F4結合） | SI案件コード | `{SI案件コード}` |
| G4:H4 `プロジェクトコード(複数可) ：` | **I4**（I4:K4結合） | プロジェクトコード | `{プロジェクトコード}` |
| R3 `作成日：` | **S3** | 作成日 | `{YYYY/MM/DD}` |
| T3 `作成者：` | **U3**（U3:V3結合） | 作成者 | `GAiDo` |

---

## 事前準備

```bash
pip install --break-system-packages lxml 2>/dev/null || true
mkdir -p ai_generated/proposals/{案件名}/risk_plan
```

> **重要**: openpyxl の `load_workbook` → `save` はテンプレート内の全 drawing を削除するため使用禁止。
> `write_checklist()`（checklist_writer.md）が `shutil.copy2` でテンプレートをコピーし `sheet2.xml` を書き込んだ後、
> 本関数が同一 output_path の `sheet4.xml` を ZIP レベルで書き込む。

---

## データ書き込みコード例

> **前提**: `write_checklist()` が `output_path` を作成済みであること。本関数はテンプレートのコピーを行わない。

```python
from datetime import date
from checklist_writer import _write_cells_to_sheet  # 同一スクリプト内に定義する場合は import 不要


def write_risk_plan(
    risk_items: list[dict],
    output_path: str,
    project_info: dict,
) -> None:
    """
    リスク管理計画シートにリスク計画データを ZIP レベルで書き込む。
    write_checklist() が shutil.copy2 で output_path を作成済みの前提で動作する。

    :param risk_items: リスク項目のリスト。各要素はdict:
        {
            "no": 1,
            "item": "新技術導入による手戻りリスク",
            "category": "TECH",         # AI内部分類（TECH/SCHED/COST/QUAL/ORG/EXT）
            "d_category": "2.要件洗い出し>11.要件・難易度",  # Excel D列用（risk_categories.md の選択肢リストから選択）
            "probability": 20,          # % (整数) ※Excel書き込み時は /100 して小数で渡すこと
            "impact_text": "PoC未実施のためフレームワーク習熟に2人月超過するリスク",
            "impact_m": 1.2,            # 百万円 (float)
            "expected_loss_m": 0.24,    # 百万円 (float) = impact_m * probability / 100
            "rank": 3,                  # Top20順位（Top20以外は None）
            "policy": "軽減",           # 回避/転嫁/軽減/受容
            "countermeasure": "事前にPoC（2週間）を実施し技術検証を完了させる",
            "is_contingency": False,    # True=コンテ, False=原価
        }
    :param output_path: write_checklist() が保存した xlsx パス（上書き対象）
    :param project_info: dict:
        {
            "customer_name": "〇〇株式会社",
            "project_name": "受発注システム刷新",
            "created_date": "2026/04/24",
            "si_code": "SI-2026-001",          # SI案件コード（省略可）
            "project_code": "PJ-2026-001",     # プロジェクトコード（省略可）
        }
    """
    today = project_info.get("created_date", date.today().strftime("%Y/%m/%d"))

    # C3/C4/G3/G4 はラベルセル（変更不要）。値は隣の結合値セルに書き込む
    updates: dict[str, str | int | float | None] = {
        "D3": project_info.get("customer_name", ""),   # C3ラベル "顧客名／SI案件名 ："
        "I3": project_info.get("project_name", ""),    # G3:H3ラベル "プロジェクト名 ："
        "D4": project_info.get("si_code", ""),         # C4ラベル "SI案件コード ："
        "I4": project_info.get("project_code", ""),    # G4:H4ラベル "プロジェクトコード(複数可) ："
        "S3": today,                                   # R3ラベル "作成日："
        "U3": "GAiDo",                                 # T3ラベル "作成者："
    }

    data_start_row = 14
    for i, risk in enumerate(risk_items):
        row = data_start_row + i
        updates[f"B{row}"] = today                              # B: 記入日
        updates[f"C{row}"] = risk["item"]                      # C: リスクイベント
        updates[f"D{row}"] = risk["d_category"]                # D: リスク観点（選択肢完全一致）
        updates[f"E{row}"] = risk["probability"] / 100         # E: 確率（小数）※パーセント書式セル
        updates[f"F{row}"] = risk["impact_text"]               # F: リスクインパクト
        updates[f"G{row}"] = risk["impact_m"]                  # G: 金額(¥M)
        # H列はテンプレートに G*E の計算式あり → 書き込まず Excel で自動計算させる
        rank = risk.get("rank")
        updates[f"I{row}"] = rank if rank and rank <= 20 else None  # I: Top20
        updates[f"J{row}"] = risk["policy"]                    # J: 対応方針
        updates[f"K{row}"] = risk["countermeasure"]            # K: 対応策
        if risk.get("is_contingency"):
            updates[f"O{row}"] = risk["expected_loss_m"]       # O: コンティンジェンシー予備費

    _write_cells_to_sheet(output_path, "xl/worksheets/sheet4.xml", updates)
    print(f"リスク管理計画シート書き込み完了: {output_path}")
```

---

## 期待損失額と順位の計算

```python
def calculate_expected_loss(probability: int, impact_m: float) -> float:
    """期待損失額（百万円） = 確率(%) × 影響度(百万円) / 100"""
    return round(probability * impact_m / 100, 3)

def assign_ranks(risk_items: list[dict]) -> list[dict]:
    """予測値の降順で Top20 順位を付与する"""
    sorted_items = sorted(
        risk_items,
        key=lambda x: x["expected_loss_m"],
        reverse=True
    )
    for rank, item in enumerate(sorted_items, start=1):
        item["rank"] = rank if rank <= 20 else ""
    return risk_items
```

---

## コンテ合計・原価合計のサマリー

```python
cont_items = [r for r in risk_items if r.get("is_contingency")]
cost_items = [r for r in risk_items if not r.get("is_contingency")]

cont_total = round(sum(r["expected_loss_m"] for r in cont_items), 3)
cost_total = round(sum(r["expected_loss_m"] for r in cost_items), 3)
total = round(cont_total + cost_total, 3)

print(f"期待損失額合計: {total}M")
print(f"コンテンジェンシー合計: {cont_total}M")
print(f"原価合計: {cost_total}M")
```

---

## エラーハンドリング

```python
import os
import zipfile
from pathlib import Path

# テンプレートの存在確認（write_checklist() 実行前に行う）
if not Path(template_path).exists():
    raise FileNotFoundError(f"テンプレートが見つかりません: {template_path}")

# output_path が write_checklist() によって作成済みか確認
if not Path(output_path).exists():
    raise FileNotFoundError(
        f"出力ファイルが存在しません: {output_path}\n"
        "write_checklist() を先に実行してください。"
    )

# 出力ファイルが Excel で開かれていないか確認（Windows のみ問題になる）
try:
    with open(output_path, "a"):
        pass
except PermissionError:
    raise PermissionError(
        f"ファイルが別のプロセスで開かれています: {output_path}\n"
        "Excel を閉じてから再実行してください。"
    )
```
