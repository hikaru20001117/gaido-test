---
name: estimate-pl-writer
description: 見積・PL生成スキルのサブスキル。他のサブスキルが抽出した構造化データを受け取り、CTC標準テンプレートに従って見積書・PLのExcelファイルを生成する。
---

# テンプレート書き込みサブスキル

## 役割

オーケストレーターから受け取った構造化データ（`extracted_data`）と見積条件（`estimate_config`）を元に、CTC標準フォーマットの見積書兼PLシートをExcelファイルとして生成する。

openpyxlでExcelファイルを生成する。数式はExcelで開いた際に自動再計算される（data_only=Falseのまま保存）。

## テンプレートファイル

`assets/template.xlsx` にテンプレートが含まれている。このファイルを直接編集してもよいが、スキルでは新規にopenpyxlで生成するアプローチを推奨する（テンプレートの構造を参考にしつつ、動的にセクション数や行数を調整できるため）。

## 入力データの形式

オーケストレーターから以下の形式でデータを受け取る：

```python
extracted_data = {
    "hardware": [...],    # hardwareサブスキルの出力（リスト of dict）
    "si": [...],          # siサブスキルの出力（リスト of dict）
    "maintenance": [...], # maintenanceサブスキルの出力（リスト of dict）
    "operation": {...},   # operationサブスキルの出力（dict）
}

estimate_config = {
    "customer_name": "ソフトバンク株式会社",
    "project_name": "ノーリツ様向けA10リプレース",
    "patterns": [
        {"name": "パターン①", "description": "2026/3/31までにメーカー発注可能な場合"},
        {"name": "パターン②", "description": "2026/3/31以降にメーカー発注となる場合"},
    ],
    "pricing": {
        "method": "margin_rate",  # "fixed", "margin_rate", "auto"
        "margin_rate": 0.30,       # 粗利率（margin_rateの場合）
    },
    "conditions": [
        "消費税金額は請求時点において施行されている消費税法等に基づき算定し、別途請求書に明記のうえ御請求致します。",
        # ...
    ],
    "hide_pl_columns": True,
    "operation_placement": "section",  # "section", "separate_sheet", "summary_only"
}
```

## 出力構成

```
シート1: 見積サマリー
シート2: パターン①
シート3: パターン②
...（パターン数に応じて動的に追加）
```

## 見積サマリーシートの生成

### レイアウト

```
行1:  (I列) =TODAY()
行2:  (A列) "{customer_name}　御中"  |  (G列) "御見積番号： "
行3:                                  |  (G列) "御見積有効期限："
行4:  (D列) "見積参考資料"
行5:  (F列) CTC社情報（下記参照）
行6:  (I列) "TEL：080-XXXX-XXXX"
行7:  (F列) "本部長" | (G列) "部長" | (H列) "課長" | (I列) "担当"
行10: (B列) "{project_name}"
行13: ヘッダー行（青背景）
行14~: パターン行（各パターンシートへの参照式）
行N:  消費税注記
行N+2~: 御見積条件
```

### CTC社情報（デフォルト値）

```
東京都港区虎ノ門4-1-1 神谷町トラストタワー
伊藤忠テクノソリューションズ株式会社
```

部署名・担当者名・TELはユーザー入力があればそちらを使い、なければ空欄にする。

### サマリーヘッダー行（行13）

| セル | 値 | スタイル |
|-----|-----|---------|
| B13 | "項番" | 背景: FF0070C0、テキスト: 白、フォント: メイリオ14pt、中央揃え |
| C13 | "概要" | 同上（C-H結合） |
| I13 | "ご提供価格" | 同上、太字、wrapText |

### パターン行（行14〜）

各パターンについて1行ずつ：

| セル | 値 |
|-----|-----|
| B{row} | "パターン①" |
| C{row} | パターンの説明（C-H結合） |
| I{row} | `=パターン①!I{提供価格の行}` |

### スタイル設定

- フォント: メイリオ 11pt
- 金額書式: `"¥"#,##0;"¥"\-#,##0`
- 結合セル: A2:C3, G2:I2, G3:I3, D4:G4, H4:I4, F5:I5, B10:I10, C13:H13, C14:H14, C15:H15
- 行高: 行1=24, 行2-3=24, 行4=28.5, 行5=90.75, 行7=19.5, 行10=21, 行13=22.5, 行14-15=34.5

## パターンシートの生成

各パターンシートは以下のセクションを動的に構成する。データがないカテゴリのセクションは省略する。

### セクション構成と行番号の管理

行番号は動的に計算する。`current_row` 変数を使って追跡する。

```python
current_row = 3  # 開始行（行3: "費用明細"）
```

### 各セクションの生成

#### SIセクション（si データがある場合）

```
行{r}:   (C列) "SI"
行{r+1}: ヘッダー行
行{r+2}~: データ行
行{r+N}: (H列) "合計" | (I列) =SUM(...)
```

ヘッダー行の列構成：

| 列 | 顧客向け | 列 | PL用（社内） |
|----|---------|-----|------------|
| B | 項 | O | 定価単価 |
| C | 型番 | P | 仕切り |
| D | 摘要 | Q | 原価 |
| E | 数量（人月） | R | 原価合計 |
| F | 定価単価 | S | 粗利 |
| G | 仕切 | T | 率 |
| H | ご提供単価 | | |
| I | ご提供合計 | | |
| J | 備考 | | |

SIデータ行の値の設定：

```python
row = current_row
sheet[f'B{row}'] = item_number          # 項番（テキスト書式）
sheet[f'C{row}'] = "ー"                  # SIは型番なし
sheet[f'D{row}'] = item['description']   # 作業内容
sheet[f'E{row}'] = item['man_months']    # 工数
sheet[f'F{row}'] = "-"                   # 定価なし
sheet[f'G{row}'] = "-"                   # 仕切なし
sheet[f'H{row}'] = selling_price         # ご提供単価（売価）
sheet[f'I{row}'] = f'=H{row}*E{row}'    # ご提供合計
# PL列
sheet[f'O{row}'] = "-"
sheet[f'P{row}'] = "^"
sheet[f'Q{row}'] = "-"
sheet[f'R{row}'] = item['cost_total']    # 原価合計（SI原価はハードコードでOK）
sheet[f'S{row}'] = f'=I{row}-R{row}'     # 粗利
sheet[f'T{row}'] = f'=S{row}/I{row}'     # 粗利率
```

#### 機器セクション（hardware データがある場合）

```
行{r}:   (C列) "機器"
行{r+1}: ヘッダー行（数量の列名は「数量（台）」）
行{r+2}~: データ行
行{r+N}: (H列) "合計" | (I列) =SUM(...)
```

機器データ行の値の設定：

```python
sheet[f'B{row}'] = item_number
sheet[f'C{row}'] = item['sku']
sheet[f'D{row}'] = item['description']
sheet[f'E{row}'] = item['quantity']
sheet[f'F{row}'] = item['list_price'] if item['list_price'] else "-"
sheet[f'G{row}'] = f'=IF(F{row}="-","-",H{row}/F{row})'  # 仕切率
sheet[f'H{row}'] = selling_price        # ご提供単価（売価）
sheet[f'I{row}'] = f'=H{row}*E{row}'
# PL列
sheet[f'O{row}'] = item['list_price'] if item['list_price'] else "-"
sheet[f'P{row}'] = f'=IF(O{row}="-","-",Q{row}/O{row})'
sheet[f'Q{row}'] = item['cost_price']    # 仕切/卸値（原価単価）
sheet[f'R{row}'] = f'=Q{row}*E{row}'     # 原価合計
sheet[f'S{row}'] = f'=I{row}-R{row}'
sheet[f'T{row}'] = f'=S{row}/I{row}'
```

#### 保守セクション（maintenance データがある場合）

```
行{r}:   (C列) "保守"
行{r+1}: ヘッダー行（数量の列名は「数量（台）」）
行{r+2}~: データ行
行{r+N}: (H列) "合計" | (I列) =SUM(...)
```

保守データ行の値の設定：

```python
sheet[f'B{row}'] = item_number
sheet[f'C{row}'] = "ー"  # 保守は型番「ー」のことが多い
sheet[f'D{row}'] = f"{item['maintenance_menu']}\n期間：{item.get('contract_period','')}ヶ月"  # 摘要に保守メニュー
sheet[f'E{row}'] = item['quantity']
sheet[f'F{row}'] = item['list_price']
sheet[f'G{row}'] = f'=IF(F{row}=0,"-",H{row}/F{row})'
sheet[f'H{row}'] = selling_price
sheet[f'I{row}'] = f'=H{row}*E{row}'
# PL列
sheet[f'O{row}'] = item['list_price']
sheet[f'P{row}'] = f'=IF(O{row}=0,"-",Q{row}/O{row})'
sheet[f'Q{row}'] = item['cost_price']
sheet[f'R{row}'] = f'=Q{row}*E{row}'
sheet[f'S{row}'] = f'=I{row}-R{row}'
sheet[f'T{row}'] = f'=S{row}/I{row}'
```

### 合計セクション

すべてのデータセクションの後に合計部分を配置する：

```python
# 原価計・粗利計ラベル行
sheet[f'R{current_row}'] = "原価計"
sheet[f'S{current_row}'] = "粗利計"
current_row += 1

# 出精値引き行
sheet[f'H{current_row}'] = "出精値引き"
# R列: 全セクションの原価合計セルを合算
sheet[f'R{current_row}'] = f'=R{si_cost_row}+R{hw_cost1_row}+...+R{maint_cost_row}'
# S列: 提供価格 - 原価計
sheet[f'S{current_row}'] = f'=I{current_row+1}-R{current_row}'
# T列: 粗利計 / 提供価格
sheet[f'T{current_row}'] = f'=S{current_row}/I{current_row+1}'
discount_row = current_row
current_row += 1

# ご提供価格行
sheet[f'H{current_row}'] = "ご提供価格"
# I列: 各セクション合計 + 出精値引き
sheet[f'I{current_row}'] = f'=I{si_total}+I{hw_total}+I{maint_total}+I{discount_row}'
price_row = current_row  # サマリーシートから参照される行番号
```

### 売価（ご提供単価）の決定方法

**カテゴリごとに算出ロジックが異なる。** 以下のルールに従って売価を決定すること。ユーザーが固定価格を指定した場合はそちらを優先する。

#### 共通ヘルパー関数

```python
import math

def round_up_1000(value):
    """下3桁を切り上げ（千円単位に切り上げ）。
    例: 1,714,286 → 1,715,000 / 294,737 → 295,000"""
    return math.ceil(value / 1000) * 1000

def determine_margin(cost_price, list_price, default_margin=0.30):
    """仕切率に基づいてマージンを決定する（機器・保守用）。
    仕切率（= 原価単価 / 定価単価）が低いほど値引きが大きい＝利益を乗せやすい。
    - 仕切率 70%以下 → 30% マージン（値引幅が大きいので利益を確保）
    - 仕切率 70%超   →  5% マージン（値引幅が小さいので薄利で提供）
    """
    if list_price is None or list_price == 0 or list_price == "-":
        return default_margin  # 定価不明の場合はデフォルト30%
    shikiri_rate = cost_price / list_price
    if shikiri_rate <= 0.70:
        return 0.30
    else:
        return 0.05
```

#### SI費用の売価算出

SIは常に **30%マージン + 千円単位切り上げ**。仕切率の概念がないためシンプル。

```python
margin = 0.30
raw_price = cost_price / (1 - margin)   # 例: 1,200,000 / 0.70 = 1,714,286
selling_price = round_up_1000(raw_price) # 例: → 1,715,000
```

#### 機器費用の売価算出

機器は **仕切率70%閾値でマージン切替 + 千円単位切り上げ**。

```python
margin = determine_margin(cost_price, list_price)
raw_price = cost_price / (1 - margin)
selling_price = round_up_1000(raw_price)
```

#### 保守費用の売価算出

保守は **仕切率70%閾値でマージン切替 + 月額ベース千円単位切り上げ + 12の倍数**。
保守は月額課金が基本なので、最終的な提供価格が12で割り切れる必要がある。

```python
margin = determine_margin(cost_price, list_price)
raw_price = cost_price / (1 - margin)
monthly = raw_price / 12                       # 月額を求める
monthly_rounded = round_up_1000(monthly)       # 月額を千円単位に切り上げ
selling_price = int(monthly_rounded * 12)      # 年額（12の倍数が保証される）
# ※ 契約期間が複数年の場合は selling_price = monthly_rounded * contract_period_months
```

#### ユーザー指定の固定価格

```python
if pricing['method'] == 'fixed':
    selling_price = pricing['prices'][item_key]  # 上記ロジックより優先
```

売価はPythonで計算してハードコードしてよい（ユーザーの意思決定を反映した値なので）。ただしご提供合計（I列）は必ずExcel数式 `=H*E` とすること。

#### 計算例

| カテゴリ | 原価単価 | 定価 | 仕切率 | マージン | 算出過程 | 売価 |
|---------|---------|------|--------|---------|---------|------|
| SI | 1,200,000 | - | - | 30% | 1,200,000/0.70=1,714,286 → 切上 | **1,715,000** |
| 機器（低仕切） | 1,577,700 | 3,506,000 | 45.0% | 30% | 1,577,700/0.70=2,253,857 → 切上 | **2,254,000** |
| 機器（高仕切） | 280,000 | 350,000 | 80.0% | 5% | 280,000/0.95=294,737 → 切上 | **295,000** |
| 保守 | 1,900,560 | 3,169,200 | 59.97% | 30% | 1,900,560/0.70=2,715,086 → 月額226,257 → 切上227,000 → ×12 | **2,724,000** |
| 保守（高仕切） | 2,500,000 | 3,200,000 | 78.1% | 5% | 2,500,000/0.95=2,631,579 → 月額219,298 → 切上220,000 → ×12 | **2,640,000** |

## フォーマット設定の詳細

### フォント

| 対象 | フォント | サイズ | 太字 |
|------|---------|--------|------|
| サマリーシート全体 | メイリオ | 11pt | × |
| サマリー顧客名 | メイリオ | 11pt | ○ |
| サマリー案件名 | メイリオ | 11pt | ○ |
| サマリーヘッダー | メイリオ | 14pt | × (I列のみ○) |
| パターンシートヘッダー | 游ゴシック | 11pt | × |
| パターンシートデータ | 游ゴシック | 12pt | × |
| パターンシートご提供価格 | 游ゴシック | 16pt | ○ |

### 数値書式

| 対象 | 書式 |
|------|------|
| 金額（売価・原価） | `"¥"#,##0;[Red]"¥"\-#,##0` |
| 仕切率・粗利率 | `0.00%` |
| 項番 | `@`（テキスト） |
| 日付 | `yyyy/m/d` |

### セルの色

| 対象 | 背景 | テキスト色 |
|------|------|-----------|
| パターンシートのヘッダー行 | theme 4, tint 0.8 | theme 1 |
| パターンシートのご提供価格行 | theme 5, tint 0.8 | theme 1, 太字 |
| サマリーのヘッダー行 | RGB FF0070C0 | theme 0（白）|

### 列幅（パターンシート）

```python
col_widths = {
    'A': 4.6, 'B': 5.9, 'C': 26.4, 'D': 62.4, 'E': 13.1,
    'F': 15.1, 'H': 20.6, 'I': 17.9, 'J': 5.6,
    'K': 3.6,  # 空白列（区切り）
    'O': 17.6, 'P': 12.3, 'Q': 12.9, 'R': 18.1, 'S': 13.9, 'T': 18.0,
}
```

### 行高（パターンシート目安）

```python
row_heights = {
    1: 30, 2: 24, 3: 30, 4: 30.75, 5: 24,
    # ヘッダー行: デフォルト
    # データ行のうち摘要が長い行: 行高を自動調整またはwrapTextで対応
    # 合計行: 約40
}
```

### 配置

| 対象 | 水平 | 垂直 | wrapText |
|------|------|------|----------|
| ヘッダーセル | center | center | × |
| 項番 | center | center | × |
| 型番 | - | center | × |
| 摘要 | - | center | ○ |
| 金額 | right | center | × |
| 合計ラベル | right | center | × |

## PL列の非表示

`estimate_config.hide_pl_columns` が `True` の場合、K-T列を非表示にする：

```python
for col_letter in ['K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T']:
    ws.column_dimensions[col_letter].hidden = True
```

## 数式の検証

ファイル生成後、openpyxlで再度ファイルを開き、数式が正しく設定されていることを確認する。
値自体の再計算はExcelで開いた際に自動で行われる。

よくあるエラーと対策：
- `#DIV/0!`: 定価が"-"や0の場合の仕切率計算 → `=IF(F{row}="-","-",IF(F{row}=0,"-",H{row}/F{row}))` のようにIF文でガード
- `#VALUE!`: テキスト「-」が入ったセルを算術式で参照 → IF文で「-」を判定してから計算
- `#REF!`: 行番号のズレ → current_rowの追跡が正しいか確認

## 出力

完成したExcelファイルを指定のパスに保存する。
