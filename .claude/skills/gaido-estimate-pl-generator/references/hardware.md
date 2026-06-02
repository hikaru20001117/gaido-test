---
name: estimate-pl-hardware
description: 見積・PL生成スキルのサブスキル。機器費用（ハードウェア費用）の入力ファイルを読み取り、型番・数量・原価等の構造化データを抽出する。
---

# 機器費用処理サブスキル

## 役割

ベンダー見積書や機器一覧などの入力ファイルから、機器（ハードウェア）に関するコスト情報を抽出し、構造化データとして返す。

## 入力

ユーザーがアップロードした機器費用関連のファイル（Excel / PDF / PowerPoint / CSV）。

## 抽出すべき情報

各機器アイテムについて以下を抽出する：

| フィールド | 説明 | 必須 |
|-----------|------|------|
| sku | 型番（SKU番号） | ○ |
| description | 摘要（製品名・説明） | ○ |
| quantity | 数量（台数） | ○ |
| list_price | 定価単価（メーカー定価） | △（ない場合あり） |
| cost_price | 仕切/卸値（＝原価単価） | ○ |
| cost_total | 原価合計（cost_price × quantity） | ○ |

## ファイル読み取りの手順

### 1. ファイルを開いて全体を俯瞰する

```python
# .xlsx の場合
import openpyxl
wb = openpyxl.load_workbook(filepath)
print(wb.sheetnames)
for name in wb.sheetnames:
    ws = wb[name]
    print(f"{name}: rows={ws.max_row}, cols={ws.max_column}")

# .xls の場合
import xlrd
wb = xlrd.open_workbook(filepath)
for sheet in wb.sheet_names():
    ws = wb.sheet_by_name(sheet)
    print(f"{sheet}: rows={ws.nrows}, cols={ws.ncols}")
# xlrd がなければ: pip install xlrd --break-system-packages

# .pdf / .pptx の場合は .claude/rules/constraints.md のルールに従う
# PDF: pdfinfo でページ数確認 → Read tool の pages パラメータで読む
# PPTX: libreoffice --headless --norestore --convert-to pdf で変換 → Read toolで読む
```

### 2. ヘッダー行を探す

以下のキーワードでヘッダー行を特定する：

**英語系**（ベンダー見積に多い）: `SKU`, `Description`, `Quantity`, `Qty`, `Price`, `Unit Price`, `Net Price`, `Total`, `Quote`

**日本語系**: `型番`, `摘要`, `品名`, `数量`, `台数`, `定価`, `単価`, `卸値`, `仕切`, `金額`, `合計`

### 3. 列をマッピングする

ヘッダーのテキストから、各列がどのフィールドに対応するかを判断する。よくあるパターン：

| ヘッダーのバリエーション | マッピング先 |
|------------------------|------------|
| SKU, 型番, Part Number, 品番 | sku |
| Description, SKU DESCRIPTION, 摘要, 品名 | description |
| Quantity, Qty, QTY, 数量, 台数 | quantity |
| List Price, 定価, 定価単価, メーカー希望小売価格 | list_price |
| Net Price, 卸値, 今回卸値, 仕切値, Unit Cost | cost_price |
| Total, 卸値合計, 金額, Net Total | cost_total |

### 4. データ行を抽出する

ヘッダー行の次の行からデータを読み取る。以下に注意：

- **複数Quote/セクション**: 1シート内に複数のQuote番号（例：Q-9581210, Q-9576830）が並ぶことがある。各Quoteの先頭行にQuote番号が入り、その下に品目が続く。すべてのQuoteからデータを抽出する。
- **合計行の除外**: `SUM` 式やラベル「合計」「Total」がある行はデータではなく集計行なので除外する。
- **空行の扱い**: Quote間に空行があることがある。空行はスキップして次のデータを読み続ける。
- **複数シート**: 機器費用が複数シートに分かれている場合がある（例：拠点別、Quote別）。すべてのシートを確認し、機器データを含むシートからデータを抽出する。ただし「提示用」等のラベルがついたシートは、元データシートの整形版である可能性があるので重複に注意する。

### 5. 抽出結果をユーザーに報告する

抽出が終わったら、概要をユーザーに報告する：

```
機器費用を読み取りました。

- シート「⑴大阪拠点_回線増速」: 3 Quote、計12品目
- シート「⑵大阪拠点_Mistソリューション」: 4 Quote、計36品目
- 原価合計: 約20,700,223円

上記の内容で合っていますか？問題なければ次に進みます。
```

## 出力形式

以下のPythonリスト形式で返す。オーケストレーターがこのデータをwriterサブスキルに渡す。

```python
hardware_items = [
    {
        "sku": "EX4100-24T",
        "description": "EX4100 24-PORT",
        "quantity": 50,
        "list_price": None,       # 不明な場合はNone
        "cost_price": 120975,     # 卸値（単価）
        "cost_total": 6048750,    # 卸値合計
        "source_sheet": "⑴大阪拠点_回線増速",  # 元シート名（参考情報）
        "source_quote": "Q-9581210S3",           # 元Quote番号（参考情報）
    },
    # ...
]
```

## エッジケースの処理

- **定価が不明**: `list_price = None` とする。出力テンプレートでは「-」と表示される。
- **卸値合計がなく単価×数量で計算可能**: `cost_total = cost_price * quantity` で算出する。
- **通貨が外貨**: 円以外の通貨（USD等）の場合はユーザーに為替レートを確認する。
- **同一SKUが複数行**: 別のQuoteや用途で同一SKUが複数回登場するのは正常。そのまま別アイテムとして抽出する。
