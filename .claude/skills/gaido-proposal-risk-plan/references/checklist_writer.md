# 案件チェックリスト書き込み手順

## 概要

`openpyxl` を使い、テンプレートの「案件チェックリスト」シートに回答を書き込む。

テンプレートファイルのパス（SKILL.md と同じディレクトリからの相対パス）:
```
assets/risk_templete.xlsx
```

---

## シート構造

シート名: **案件チェックリスト**

### ヘッダー部分（2〜5行目）

B2:C2・B3:C3・B4:C4・B5:C5 は結合ラベルセル（変更不要）。値は隣の結合値セルに書き込む。

| ラベルセル（変更不要） | 値を書き込むセル | 書き込む値 |
|---------------------|----------------|----------|
| B2:C2 `顧客名/SI案件名：` | **D2** | `{顧客名}` |
| B3:C3 `案件名：` | **D3** | `{案件名}` |
| B4:C4 `日付：` | **D4** | `{YYYY/MM/DD}` |
| B5:C5 `契約違反時の損害賠償の上限：` | **D5** | `{金額または「未確認」}` |

### データ行構造

ヘッダー行: **7行目**
セクションヘッダー行（書き込み不要）: 8, 14, 25, 29, 37 行目
データ行: 9〜38行目（セクションヘッダー行を除く）

| 列 | ヘッダー | 書き込む内容 |
|----|---------|------------|
| A | № | 変更不要 |
| B | 案件規模 | 変更不要 |
| C | リスク観点 | 変更不要 |
| D | チェック項目 | 変更不要 |
| E | 回答 | **「Yes」または「No」**（案件規模条件対象外の場合は空欄） |
| F | （空） | 変更不要 |
| G | 説明 | 変更不要 |
| H | リスク有無 | **「リスク有」または「リスク無」**（案件規模条件対象外の場合は空欄） |

---

## H列のリスク判定ロジック

テンプレートの H 列には条件テキストが記述されている。これを読んで判定結果（「リスク有」/「リスク無」）を書き込む。

| テンプレートの H 列値 | 判定ルール |
|-------------------|----------|
| `No\nの場合リスク有` | E 列が「No」→「リスク有」、「Yes」→「リスク無」 |
| `Yes\nの場合リスク有` | E 列が「Yes」→「リスク有」、「No」→「リスク無」 |

```python
def determine_risk(answer: str, h_template_value: str) -> str:
    """
    E列の回答とH列のテンプレート条件からリスク有無を決定する。

    :param answer: "Yes" または "No"
    :param h_template_value: テンプレートH列の元の値（"No\nの場合リスク有..." 等）
    :return: "リスク有" または "リスク無"
    """
    risky_answer = "Yes" if h_template_value.startswith("Yes") else "No"
    return "リスク有" if answer == risky_answer else "リスク無"
```

---

## 案件規模フィルタ

- B 列が `「全案件」`: 案件規模によらず常に回答する
- B 列が `「3000万円以上」`: 案件規模が 3000万円以上の場合のみ E/H 列を記入する。3000万円未満の案件では空欄のままにする

---

## 全チェック項目一覧

| 行 | No | 案件規模 | リスク観点（C列） | チェック項目（D列・要約） | H条件 | リスク管理計画D列対応値 |
|----|-----|---------|----------------|----------------------|------|---------------------|
| 9 | 1 | 3000万円以上 | 顧客 | 顧客はプロジェクトの主体性をもっているか | No→リスク有 | `1.スコープ定義>1.顧客` |
| 10 | 2 | 3000万円以上 | 顧客・体制 | 顧客体制の大きな変更が予想されるか | Yes→リスク有 | `1.スコープ定義>2.顧客・体制` |
| 11 | 3 | 全案件 | 顧客・契約 | 顧客との契約において不要な責任を負うことを回避できているか | No→リスク有 | `1.スコープ定義>3.顧客・契約` |
| 12 | 4 | 3000万円以上 | 社内・体制 | 社内体制の大きな変更が予想されるか | Yes→リスク有 | `1.スコープ定義>4.社内・体制` |
| 13 | 5 | 3000万円以上 | 工期・納期 | 根拠に基づいた適正な工期を確保しているか | No→リスク有 | `1.スコープ定義>5.工期・納期` |
| 15 | 6 | 全案件 | 役割・責任 | 顧客・CTC・委託先の役割・責任範囲は明確になっているか | No→リスク有 | `2.要件洗い出し>6.役割・責任` |
| 16 | 7 | 全案件 | コミュニケーション | 顧客・委託先との会議体・窓口などのコミュニケーションルートは明確か | No→リスク有 | `2.要件洗い出し>7.コミュニケーション` |
| 17 | 8 | 全案件 | 要求・要件 | 顧客要求を思い込みや想定で判断していないか | No→リスク有 | `2.要件洗い出し>8〜10.要求・要件` |
| 18 | 9 | 全案件 | 要求・要件 | RFP・ヒアリング等で顧客要求に曖昧な部分があるか | Yes→リスク有 | `2.要件洗い出し>8〜10.要求・要件` |
| 19 | 10 | 全案件 | 要求・要件 | 見積の変動要素となる要件を抜け漏れなく定義できているか | No→リスク有 | `2.要件洗い出し>8〜10.要求・要件` |
| 20 | 11 | 全案件 | 要件・難易度 | 要件に対する案件の難易度を把握しているか | No→リスク有 | `2.要件洗い出し>11.要件・難易度` |
| 21 | 12 | 全案件 | 要件・法令 | 個別に遵守すべき法律・法令はないか | No→リスク有 | `2.要件洗い出し>12.要件・法令` |
| 22 | 13 | 全案件 | 要件・コンプライアンス | 顧客要求/要件が法律・法令・コンプライアンスに抵触していないか | No→リスク有 | `2.要件洗い出し>13.要件・コンプライアンス` |
| 23 | 14 | 全案件 | パッケージ・製品 | 選定したパッケージや製品は顧客要求・要件を満たしているか | No→リスク有 | `2.要件洗い出し>14.パッケージ・製品` |
| 24 | 15 | 全案件 | AIシステム | AIシステムである場合、固有のリスクを把握・対策しているか | No→リスク有 | `2.要件洗い出し>15.AIシステム` |
| 26 | 16 | 全案件 | 成果物、タスク | 必要なタスク・成果物に抜け漏れが無いか | No→リスク有 | `3.作業洗い出し(WBS)>16.成果物、タスク` |
| 27 | 17 | 全案件 | パッケージ・製品 | 選定したパッケージや製品に対して事前の検証作業が計画されているか | No→リスク有 | `3.作業洗い出し(WBS)>17.パッケージ・製品` |
| 28 | 18 | 3000万円以上 | オフショア | オフショア特有の作業や経費を考慮しているか | No→リスク有 | `3.作業洗い出し(WBS)>18.オフショア` |
| 30 | 19 | 全案件 | PM | PMは当該プロジェクトと同等の業務・規模の経験を有しているか | No→リスク有 | `4.要員計画>19.PM` |
| 31 | 20 | 全案件 | 社内・体制 | プロジェクトで求められるスキルを有した要員確保の目処は立っているか | No→リスク有 | `4.要員計画>20.社内・体制` |
| 32 | 21 | 全案件 | 社内・組織支援 | 組織の支援体制が計画されているか | No→リスク有 | `4.要員計画>21.社内・組織支援` |
| 33 | 22 | 全案件 | 委託先・見積 | 委託先の見積が適正な範囲であり、見積根拠は妥当であるか | No→リスク有 | `4.要員計画>22.委託先・見積` |
| 34 | 23 | 3000万円以上 | 委託先・動員力 | 委託先は専任アサイン・緊急時の追加など柔軟に対応可能か | No→リスク有 | `4.要員計画>23.委託先・動員力` |
| 35 | 24 | 3000万円以上 | 委託先・経営状況 | 委託先の経営状況に問題はないか | No→リスク有 | `4.要員計画>24.委託先・経営状況` |
| 36 | 25 | 3000万円以上 | パッケージ・製品 | 選定したパッケージや製品のベンダから必要な支援が受けられるか | No→リスク有 | `4.要員計画>25.パッケージ・製品` |
| 38 | 26 | 全案件 | 成果物、タスク | 成果物の量と品質に応じた作業工数・作業期間が計画されているか | No→リスク有 | `5.作業計画>26.成果物、タスク` |

---

## データ書き込みコード例

> **重要**: openpyxl の `load_workbook` → `save` はテンプレート内の `xl/drawings/` を全削除・`_rels`・`[Content_Types].xml` も書き換えるため使用禁止。
> 代わりに `shutil.copy2` でテンプレートをそのままコピーし、ZIP レベルでセル値のみ書き換える。

### `_write_cells_to_sheet()` — ZIP レベルセル書き込み共通ヘルパー

```python
import zipfile
from datetime import date
from pathlib import Path
from lxml import etree

WS_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"


def _write_cells_to_sheet(
    xlsx_path: str,
    sheet_zip_path: str,
    updates: dict[str, "str | int | float | None"],
) -> None:
    """
    xlsx の指定シート XML にセル値を ZIP レベルで書き込む。
    openpyxl を使わないため drawing・styles・_rels を破壊しない。

    書き込みルール（テンプレートに存在しないセル/行はスキップ）:
    - str 値    → t="inlineStr"、<is><t>value</t></is>（スタイル s= は保持）
    - int/float → t 属性を削除（数値デフォルト）、<v>value</v>
    - None 値   → スキップ

    :param xlsx_path: 上書き対象の xlsx ファイルパス
    :param sheet_zip_path: ZIP 内のシートパス（例: "xl/worksheets/sheet2.xml"）
    :param updates: {セル参照: 値} 例: {"B2": "顧客名：ABC", "E9": "Yes", "G14": 3.0}
    """
    tmp_path = xlsx_path + ".cwtmp"

    with zipfile.ZipFile(xlsx_path, "r") as zin:
        ws_root = etree.fromstring(zin.read(sheet_zip_path))
        sd = ws_root.find(f"{{{WS_NS}}}sheetData")
        row_map = {r.get("r"): r for r in sd}

        for cell_ref, value in updates.items():
            if value is None:
                continue
            row_num = "".join(filter(str.isdigit, cell_ref))
            if row_num not in row_map:
                continue  # テンプレートに存在しない行はスキップ
            row_elem = row_map[row_num]
            cell_elem = next((c for c in row_elem if c.get("r") == cell_ref), None)
            if cell_elem is None:
                continue  # テンプレートに存在しないセルはスキップ

            # 既存の <v> / <is> / <f>（計算式）を削除
            for child in list(cell_elem):
                tag = child.tag.split("}")[-1] if "}" in child.tag else child.tag
                if tag in ("v", "is", "f"):
                    cell_elem.remove(child)

            if isinstance(value, str):
                # 文字列: inline string（スタイル s= は保持）
                cell_elem.set("t", "inlineStr")
                is_elem = etree.SubElement(cell_elem, f"{{{WS_NS}}}is")
                t_elem = etree.SubElement(is_elem, f"{{{WS_NS}}}t")
                t_elem.text = value
            else:
                # 数値: t 属性を削除して <v> に値を設定
                if "t" in cell_elem.attrib:
                    del cell_elem.attrib["t"]
                v_elem = etree.SubElement(cell_elem, f"{{{WS_NS}}}v")
                v_elem.text = str(value)

        with zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.namelist():
                if item == sheet_zip_path:
                    zout.writestr(
                        item,
                        etree.tostring(ws_root, xml_declaration=True, encoding="UTF-8"),
                    )
                else:
                    zout.writestr(item, zin.read(item))

    Path(tmp_path).replace(xlsx_path)
```

### `write_checklist()` — 案件チェックリスト書き込み

```python
import shutil


def write_checklist(
    checklist_items: list[dict],
    output_path: str,
    template_path: str,
    project_info: dict,
) -> None:
    """
    案件チェックリスト回答を Excel テンプレートに書き込む。
    テンプレートを shutil.copy2 でコピーし、ZIP レベルでセル値のみ書き換える。

    :param checklist_items: チェックリスト回答リスト。各要素はdict:
        {
            "row": 9,                  # Excel 行番号
            "no": 1,                   # チェック項目番号
            "scale": "3000万円以上",    # "全案件" or "3000万円以上"
            "answer": "No",            # E列: "Yes" または "No"
            "risk_result": "リスク有",  # H列: "リスク有" または "リスク無"
            "confidence": "確信",       # "確信" または "要確認"
            "d_category": "1.スコープ定義>1.顧客",  # リスク管理計画D列対応値
            "check_text": "顧客はプロジェクトの主体性をもっているか",
            "is_applicable": True,     # 案件規模条件を満たしているか
        }
    :param output_path: 出力先パス
    :param template_path: テンプレートファイルパス
    :param project_info: dict:
        {
            "customer_name": "〇〇株式会社",
            "project_name": "受発注システム刷新",
            "created_date": "2026/04/24",
            "penalty_limit": "契約金額の1倍",  # 契約違反時の損害賠償上限
        }
    """
    # 1. テンプレートをそのままコピー（drawing・styles・_rels 等をすべて保持）
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(template_path, output_path)

    today = project_info.get("created_date", date.today().strftime("%Y/%m/%d"))

    # 2. 書き込むセル値を構築
    # B2:C2 / B3:C3 / B4:C4 / B5:C5 は結合ラベルセル（変更不要）
    # 値は隣の結合値セル D2 / D3 / D4 / D5 に書き込む
    updates: dict[str, str | None] = {
        "D2": project_info.get("customer_name", ""),
        "D3": project_info.get("project_name", ""),
        "D4": today,
        "D5": project_info.get("penalty_limit", "未確認"),
    }
    for item in checklist_items:
        if item.get("is_applicable", True):
            row = item["row"]
            updates[f"E{row}"] = item["answer"]
            updates[f"H{row}"] = item["risk_result"]

    # 3. ZIP レベルでセル値を書き込む
    _write_cells_to_sheet(output_path, "xl/worksheets/sheet2.xml", updates)

    # 4. 要確認バッジを追加（confidence=要確認 かつ リスク無 の行）
    badge_rows = [
        item["row"]
        for item in checklist_items
        if item.get("is_applicable", True)
        and item.get("confidence") == "要確認"
        and item.get("risk_result") == "リスク無"
    ]
    add_yoKakunin_badges(output_path, badge_rows)
    print(f"保存完了: {output_path}")
```

---

## チェックリスト→リスク管理計画シート変換

チェックリストの「リスク有」項目を `excel_writer.md` の `write_risk_plan()` に渡す形式に変換する。
`probability` / `impact_m` / `policy` / `countermeasure` 等は後続ステップ（Step 5〜9）でAIが付与する。

```python
def checklist_to_risk_stubs(checklist_items: list[dict]) -> list[dict]:
    """
    チェックリストのリスク有項目を、リスク管理計画シート書き込み用の雛形リストに変換する。

    :param checklist_items: write_checklist() に渡したものと同じリスト
    :return: risk_stubs リスト（probability 等は後続ステップで補完）
    """
    stubs = []
    for item in checklist_items:
        if item.get("is_applicable") and item.get("risk_result") == "リスク有":
            stubs.append({
                "d_category": item["d_category"],
                "check_text": item["check_text"],  # リスクイベント（C列）生成の参考用
                # 以下は Step 5〜9 で付与する
                "item": "",
                "category": "",
                "probability": None,
                "impact_text": "",
                "impact_m": None,
                "expected_loss_m": None,
                "rank": None,
                "policy": "",
                "countermeasure": "",
                "is_contingency": False,
            })
    return stubs
```

---

---

## 要確認バッジの描画

`confidence = 要確認` かつ `リスク無` の行に、黄色の楕円図形＋「要確認」テキストを J 列右端へオーバーレイする。

openpyxl の Shape API が楕円テキストをサポートしないため、保存済み xlsx（ZIP）を直接編集して drawing XML へ注入する。

### 配置仕様

| 項目 | 値 |
|-----|-----|
| 位置 | J 列（col 9, 0-indexed）の右端から K 列中央まで |
| 塗りつぶし | 黄色 `#FFFF00` |
| 枠線 | 暗黄色 `#CC9900`、太さ 1.5pt |
| テキスト | `要確認`、太字、11pt、中央揃え |

### `_build_oval_anchor()` — XML 要素生成

```python
from lxml import etree

XDR_NS = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
A_NS   = "http://schemas.openxmlformats.org/drawingml/2006/main"


def _build_oval_anchor(row_idx: int, shape_id: int) -> etree._Element:
    """
    要確認楕円バッジの twoCellAnchor XML 要素を生成する。

    :param row_idx: 1-indexed 行番号
    :param shape_id: ワークブック内で一意な整数 ID
    :return: lxml Element（xdr:twoCellAnchor）
    """
    row0 = row_idx - 1  # xdr の row は 0-indexed
    xml = (
        f'<xdr:twoCellAnchor xmlns:xdr="{XDR_NS}" xmlns:a="{A_NS}" editAs="oneCell">'
        f'<xdr:from><xdr:col>9</xdr:col><xdr:colOff>114300</xdr:colOff>'
        f'<xdr:row>{row0}</xdr:row><xdr:rowOff>114300</xdr:rowOff></xdr:from>'
        f'<xdr:to><xdr:col>11</xdr:col><xdr:colOff>0</xdr:colOff>'
        f'<xdr:row>{row0 + 1}</xdr:row><xdr:rowOff>-114300</xdr:rowOff></xdr:to>'
        f'<xdr:sp macro="" textlink="">'
        f'<xdr:nvSpPr>'
        f'<xdr:cNvPr id="{shape_id}" name="Oval{shape_id}"/>'
        f'<xdr:cNvSpPr><a:spLocks noGrp="1"/></xdr:cNvSpPr>'
        f'</xdr:nvSpPr>'
        f'<xdr:spPr>'
        f'<a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>'
        f'<a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom>'
        f'<a:solidFill><a:srgbClr val="FFFF00"/></a:solidFill>'
        f'<a:ln w="19050"><a:solidFill><a:srgbClr val="CC9900"/></a:solidFill></a:ln>'
        f'</xdr:spPr>'
        f'<xdr:txBody>'
        f'<a:bodyPr anchor="ctr" anchorCtr="1"/><a:lstStyle/>'
        f'<a:p><a:pPr algn="ctr"/>'
        f'<a:r><a:rPr lang="ja-JP" sz="1100" b="1" dirty="0"/>'
        f'<a:t>要確認</a:t></a:r></a:p>'
        f'</xdr:txBody>'
        f'</xdr:sp>'
        f'<xdr:clientData/>'
        f'</xdr:twoCellAnchor>'
    )
    return etree.fromstring(xml)
```

### `add_yoKakunin_badges()` — ZIP 直接編集

```python
import zipfile
from lxml import etree
from pathlib import Path

REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
SS_NS  = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"


def add_yoKakunin_badges(xlsx_path: str, badge_rows: list[int]) -> None:
    """
    保存済み xlsx の「案件チェックリスト」シートに要確認楕円バッジを追加する。
    xlsx は ZIP 構造のため直接 drawing XML を編集して注入する。

    :param xlsx_path: 上書き対象の xlsx ファイルパス
    :param badge_rows: バッジを追加する行番号リスト（1-indexed）
    """
    if not badge_rows:
        return

    tmp_path = xlsx_path + ".tmp"

    with zipfile.ZipFile(xlsx_path, "r") as zin:
        names = set(zin.namelist())

        # --- 案件チェックリストのシートファイルパスを特定 ---
        wb_xml = etree.fromstring(zin.read("xl/workbook.xml"))
        r_id = next(
            s.get(f"{{{REL_NS}}}id")
            for s in wb_xml.iter(f"{{{SS_NS}}}sheet")
            if s.get("name") == "案件チェックリスト"
        )
        wb_rels = etree.fromstring(zin.read("xl/_rels/workbook.xml.rels"))
        sheet_target = next(
            r.get("Target") for r in wb_rels if r.get("Id") == r_id
        )
        # sheet_target 例: "worksheets/sheet1.xml"
        sheet_filename = Path(sheet_target).name
        sheet_rels_path = f"xl/worksheets/_rels/{sheet_filename}.rels"

        # --- 既存 drawing のパスを取得（なければ新規作成） ---
        drawing_path: str | None = None
        if sheet_rels_path in names:
            sheet_rels = etree.fromstring(zin.read(sheet_rels_path))
            for rel in sheet_rels:
                if "drawing" in rel.get("Type", "").lower():
                    # Target 例: "../drawings/drawing1.xml"
                    target = rel.get("Target", "")
                    drawing_path = "xl/" + target.lstrip("../")
                    break

        if drawing_path and drawing_path in names:
            drawing_root = etree.fromstring(zin.read(drawing_path))
        else:
            # drawing が存在しない場合は空の wsDr を作成
            # ※ このケースでは sheet rels / [Content_Types].xml の追記も必要。
            #   テンプレートに既存 drawing がある前提のため、ここではエラーとする。
            raise RuntimeError(
                f"案件チェックリストの drawing ファイルが見つかりません。"
                f"テンプレートに drawing が存在することを確認してください。"
            )

        # --- バッジ要素を drawing に追加 ---
        for i, row_idx in enumerate(badge_rows, start=1):
            drawing_root.append(_build_oval_anchor(row_idx, shape_id=100 + i))

        # --- ZIP を再構築して上書き保存 ---
        with zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in names:
                if item == drawing_path:
                    zout.writestr(
                        item,
                        etree.tostring(drawing_root, xml_declaration=True, encoding="UTF-8"),
                    )
                else:
                    zout.writestr(item, zin.read(item))

    Path(tmp_path).replace(xlsx_path)
```

> **注意**: `shape_id` は `100 +` から開始してテンプレート既存図形との衝突を避ける。
> テンプレートに drawing が存在しない場合は `RuntimeError` を出すため、必ずテンプレートを確認すること。

---

## 両シートを書き込む場合

案件チェックリストとリスク管理計画シートは同一 xlsx ファイルに書き込む。
**openpyxl の `load_workbook` / `save` は使用禁止**（drawing 全消失のため）。
以下の順序で ZIP レベル操作を行う:

```python
import shutil

# 1. テンプレートを出力先にコピー（1回のみ）
shutil.copy2(template_path, output_path)

# 2. 案件チェックリスト（sheet2.xml）に書き込む
_write_cells_to_sheet(output_path, "xl/worksheets/sheet2.xml", checklist_updates)

# 3. リスク管理計画シート（sheet4.xml）に書き込む（excel_writer.md 参照）
_write_cells_to_sheet(output_path, "xl/worksheets/sheet4.xml", risk_plan_updates)

# 4. 要確認バッジを追加（案件チェックリストの drawing に注入）
add_yoKakunin_badges(output_path, badge_rows)
```

`_write_cells_to_sheet()` は本ファイルで定義。`write_risk_plan()` の詳細は `excel_writer.md` 参照。
