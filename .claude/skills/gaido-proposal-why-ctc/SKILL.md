---
name: gaido-proposal-why-ctc
description: SharePointからWhy CTC素材を収集してwhy_ctc_materials.mdを生成する。gaido-proposal-initのStep 3.5から呼び出される。
---

# Why CTC 素材収集

## 概要

提案書の「CTCの優位性」スライドを充実させるため、
SharePointから社内実績・事例・会社紹介資料を検索・収集し、
`ai_generated/proposals/{案件名}/why_ctc_materials.md` に素材をまとめる。

### 2フェーズ検索方式

SharePoint検索は **2段階** で行う。

1. **Phase 1（探索）**: rfp_summary.md から抽出した業界・課題キーワードで大まかに検索し、
   ヒット文書のタイトル・抜粋から **関連製品名・ベンダー名** を自動発見する。
   - 例: 「DWH 実績」で検索 → 「Snowflake」「Databricks」「Teradata」を発見

2. **Phase 2（収集）**: Phase 1 で発見した製品名も加えたキーワードセットで絞り込み検索し、
   Why CTCスライドの素材として `why_ctc_materials.md` にまとめる。

この方式により、RFPにハードコードされていない製品名でも自動発見でき、
DWH・サーバー構築・ネットワーク・セキュリティなど全SI領域に対応する。

SharePoint認証（`.ms365/credentials.json`）が用意されていない場合は、
スキップ旨を記載したフォールバック版の `why_ctc_materials.md` を生成して完了する。
**認証がなくても後続フロー（Step 3.6以降）は続行される。**

## 引数

```
/gaido-proposal-why-ctc {案件名}
```

案件名が指定されていない場合は AskUserQuestion で確認する。

## 実行手順

### Step 1: 提案テーマの取得

`ai_generated/proposals/{案件名}/rfp_summary.md` が存在する場合は Read ツールで読み込む。

ファイルが存在しない場合は、Box資料なしの直接入力モードとして AskUserQuestion で提案テーマを確認する:

```
AskUserQuestion(
  questions=[
    {
      "question": "提案テーマを入力してください。SharePointからその分野の社内実績・事例を収集します。",
      "header": "提案テーマ",
      "multiSelect": false,
      "options": [
        {"label": "ストレージ提案", "description": "例: ファイルアクセス改善のためのNAS/ストレージ提案"},
        {"label": "クラウド移行提案", "description": "例: オンプレミスからAzure/AWSへの移行提案"},
        {"label": "セキュリティ提案", "description": "例: ゼロトラスト・エンドポイントセキュリティ導入"},
        {"label": "ネットワーク提案", "description": "例: 拠点間ネットワーク刷新・SD-WAN導入"}
      ]
    }
  ]
)
```

「Other」でユーザーが自由入力した場合も含め、入力されたテーマテキストを rfp_summary.md 相当の情報として Step 2 以降で使用する。

### Step 2: 探索キーワードの抽出

rfp_summary.md の内容から、Phase 1（探索）に使う **大まかなドメインキーワード** を3〜5語抽出する。

抽出の観点（製品名ではなく、領域・課題・業界レベルのキーワード）:
- **業界・課題レベル**: 「DWH 実績」「クラウド移行 事例」「ネットワーク 構築」「セキュリティ 実績」
- **顧客業種**: 「製造業 SI」「金融 導入事例」「官公庁 実績」
- **CTC強み領域**: 「Cisco 導入事例」「NetApp 実績」「Azure SI」

このステップでは **製品名は不要**。Phase 1 でSharePointから自動発見する。

### Step 3: トークン確認

`.ms365/credentials.json` の存在と `access_token` の有効期限を確認する:

```bash
python3 -c "
import json, time, sys
from pathlib import Path
p = Path('.ms365/credentials.json')
if not p.exists():
    print('TOKEN_MISSING')
    sys.exit(0)
try:
    data = json.loads(p.read_text())
    access_token = data.get('access_token', '')
    expires_at = data.get('expires_at', 0)
    if not access_token:
        print('TOKEN_MISSING')
        sys.exit(0)
    remaining = expires_at - int(time.time())
    if remaining <= 0:
        print(f'TOKEN_EXPIRED:{-remaining}')
    else:
        print(f'TOKEN_OK:{remaining}')
except Exception as e:
    print(f'TOKEN_ERROR:{e}')
"
```

- `TOKEN_MISSING` または `TOKEN_EXPIRED:*` → Step 7（フォールバック生成）へ進み、認証手順を案内する
- `TOKEN_OK:*` → Step 4（Phase 1）へ進む

### Step 4: Phase 1（探索） — 製品名・ベンダー名の自動発見

Step 2 で抽出した探索キーワード（最大3語）を使い、SharePointを大まかに検索する。
各キーワードについて以下を実行:

```bash
python3 tools/ms365_client.py "{探索キーワード}" --top 15 --out-dir /tmp/ms365_why_ctc_phase1 2>&1
```

実行結果からヒット文書の **文書名（name）** と **本文抜粋（summary）** を読み取り、
以下の手がかりとなる語を抽出する:

- **製品名・ソリューション名**: Snowflake / Databricks / Teradata / VMware / Nutanix / Palo Alto / Fortinet 等
- **ベンダー名**: Dell / HPE / Juniper / Check Point 等
- **サービス・プラットフォーム名**: Salesforce / ServiceNow / Microsoft 365 等

抽出した語を「Phase 1 発見キーワード」としてリストアップする。
文書名・抜粋に出現した語だけを対象とし、知識から補完してはならない。

### Step 4.5: Phase 1.5（EOL確認）— 製品販売状況の確認

Phase 1 で発見した製品名・ベンダー名について、SharePoint上の販売終了・サポート終了情報を確認する。
発見した製品名ごとに以下のキーワードパターンで検索する（最大5製品まで）:

```bash
python3 tools/ms365_client.py "{製品名} EOL" --top 5 --out-dir /tmp/ms365_eol_check 2>&1
python3 tools/ms365_client.py "{製品名} 販売終了" --top 5 --out-dir /tmp/ms365_eol_check 2>&1
python3 tools/ms365_client.py "{製品名} EOA 販売終息" --top 5 --out-dir /tmp/ms365_eol_check 2>&1
```

ヒットした文書から以下の情報を優先的に抽出する:
- 販売終了日・サポート終了日
- 後継製品名
- 文書名・SharePoint URL

**EOL文書がヒットしなかった場合**: Step 5 へ進む。

**EOL文書がヒットした場合**: 以下の形式でユーザーに警告を提示する:

```
AskUserQuestion(
  questions=[
    {
      "question": "以下の製品に販売終了・サポート終了（EOL/EOA/販売終息）の可能性があります。提案に含める前に確認してください。\n\n{製品名: 文書名, 販売終了日（記載があれば）, 後継製品（記載があれば）の一覧}",
      "header": "販売状況警告",
      "multiSelect": false,
      "options": [
        {"label": "内容を確認して続行する", "description": "EOL情報を把握した上でWhy CTC素材収集（Phase 2）に進みます"},
        {"label": "提案を見直す（ここで停止）", "description": "EOL製品が含まれているため提案を見直してから再実行します"}
      ]
    }
  ]
)
```

「提案を見直す（ここで停止）」が選択された場合は Step 7（EOL警告版）へ進み、EOL警告のみ記載した `why_ctc_materials.md` を生成して終了する。

### Step 5: キーワード確認（AskUserQuestion）

Phase 1 で発見したキーワードと、Step 2 で抽出した探索キーワードを合わせて提示し、
Phase 2（収集）に使うキーワードセットをユーザーに確認する。

```
AskUserQuestion(
  questions=[
    {
      "question": "Phase 1探索でSharePointから以下のキーワードが見つかりました。Phase 2の収集検索に使うキーワードを確認してください。修正したい場合はOtherで入力してください（スペース区切りで複数指定可）。",
      "header": "検索キーワード確認",
      "multiSelect": false,
      "options": [
        {"label": "このキーワードで検索する", "description": "提示したキーワードでSharePointをPhase 2検索します: {探索キーワード + Phase 1発見キーワード一覧}"},
        {"label": "SharePoint検索をスキップ", "description": "SharePoint検索を行わずwhy_ctc_materials.mdをスキップ版で生成します"}
      ]
    }
  ]
)
```

「SharePoint検索をスキップ」が選択された場合はStep 7（フォールバック生成）へ進む。

### Step 6: Phase 2（収集） — 絞り込み検索と素材収集

確認済みキーワード（最大8キーワードまで）を使い、キーワードごとに `ms365_client.py` を実行する。

```bash
python3 tools/ms365_client.py "{キーワード}" --top 10 --out-dir /tmp/ms365_why_ctc_phase2 2>&1
```

実行結果から以下を収集する:
- 文書名 (`name`)
- SharePoint URL (`webUrl`)
- 更新日 (`lastModifiedDateTime`)
- 本文抜粋 (`summary` の `<c0>` タグ除去済みテキスト)
- ダウンロード済みテキストファイル（`/tmp/ms365_why_ctc_phase2/*.txt`）の内容（存在する場合）

収集した文書から、Why CTCスライドに使えそうな情報を抽出・整理する:
- CTC社の実績・導入事例（顧客名・規模・課題・解決策）
- CTC社の技術力・強み（得意な製品・技術領域）
- 提案テーマに関連する実績（キーワードとの関連度）

### Step 7: why_ctc_materials.md の生成・Boxアップロード

`ai_generated/proposals/{案件名}/why_ctc_materials.md` に素材をまとめる。

生成後、`.box/credentials.json` が存在する場合は Box にアップロードする:

```bash
python3 tools/box_client.py upload \
  ai_generated/proposals/{案件名}/why_ctc_materials.md \
  --folder-path "GAiDo/{案件名}/proposal"
```

Box連携が未設定（`.box/credentials.json` がない）の場合はアップロードをスキップし、ローカルのみに保存する。

#### SharePoint検索成功時のフォーマット

```markdown
# Why CTC 素材

## 検索条件
- Phase 1（探索）キーワード: {使用した探索キーワード一覧}
- Phase 2（収集）キーワード: {使用した収集キーワード一覧（Phase 1発見キーワード含む）}
- 検索日時: {YYYY-MM-DD}

## Phase 1 発見キーワード
Phase 1の探索検索でSharePoint文書から自動発見した製品名・ベンダー名:
- {発見した語1}
- {発見した語2}
（以下、発見した語の数だけ）

## 素材一覧

### 1. {文書名}
- 出典: {SharePoint URL}
- 取得日時: {YYYY-MM-DD}
- 関連キーワード: {マッチしたキーワード}
- 本文抜粋:
  {抽出した本文の要点（500文字程度。具体的な数値・顧客名・実績を優先して抽出する）}

（以下、取得した文書の数だけ繰り返し）

## Why CTCスライド作成のポイント

AIが上記の素材から読み取ったWhy CTCの核心:
- {強み・実績のポイント1}
- {強み・実績のポイント2}
- {提案テーマとの接続ポイント}

## EOL・販売状況確認結果

{EOLヒットなしの場合}
SharePoint検索においてEOL・販売終了・EOA・販売終息に関する文書はヒットしませんでした。

{EOLヒットありで続行の場合}
以下の製品についてEOL・販売状況に関する文書がSharePointで確認されました。提案に含める際は内容を精査してください。

### {製品名}
- 出典: {SharePoint URL}
- 取得日時: {YYYY-MM-DD}
- 確認内容: {販売終了日・後継製品等の抜粋}

（以下、EOLが確認された製品の数だけ繰り返し）
```

#### SharePoint検索スキップ時のフォーマット（トークンなし・ユーザースキップ）

```markdown
# Why CTC 素材

## SharePoint検索: スキップ

{理由を記載:
  - 「SharePoint認証（.ms365/credentials.json）が用意されていないためスキップしました」
  - または「ユーザーがスキップを選択しました」
}

### SharePoint認証を取得するには（トークンなし時のみ表示）

1. GAiDo デスクトップアプリの Setup Wizard で SharePoint 連携を完了する
2. `/gaido-proposal-why-ctc {案件名}` を再実行する

## Why CTCスライド作成のガイダンス

SharePoint素材が未収集のため、以下を参考にWhy CTCスライドを構成してください:
- CTC社の技術力・SI実績を強調する
- 提案テーマに関連する自社の強みを記述する
- 可能であれば担当者に実績事例を確認してください
```

#### EOL警告・停止時のフォーマット

```markdown
# Why CTC 素材

## SharePoint検索: EOL警告により停止

提案に含まれる以下の製品について、販売終了・サポート終了（EOL/EOA/販売終息）に関する文書がSharePointで確認されました。
提案内容を見直してから `/gaido-proposal-why-ctc {案件名}` を再実行してください。

## EOL・販売状況警告

### {製品名}
- 出典: {SharePoint URL}
- 取得日時: {YYYY-MM-DD}
- 確認内容: {販売終了日・後継製品等の抜粋}

（以下、EOLが確認された製品の数だけ繰り返し）
```

### Step 8: 完了報告

生成した `why_ctc_materials.md` の内容をユーザーに提示し、完了を報告する。

SharePoint検索に成功した場合:
`.box/credentials.json` が存在する場合: 「Phase 1探索で {M}件の文書からキーワードを発見し、Phase 2収集で {N}件の素材を取得しました。`ai_generated/proposals/{案件名}/why_ctc_materials.md` に保存しました（Box連携あり: BoxのGAiDo/{案件名}/proposalにもアップロード済み）。Step 4以降のストーリー壁打ちでこの素材を活用します。」
`.box/credentials.json` が存在しない場合: 「Phase 1探索で {M}件の文書からキーワードを発見し、Phase 2収集で {N}件の素材を取得しました。`ai_generated/proposals/{案件名}/why_ctc_materials.md` に保存しました（Box未連携のためローカル保存となります。Box連携を有効にすると、この成果物が自動でBoxに保存されます。GAiDoアプリの Step 4 で設定できます）。Step 4以降のストーリー壁打ちでこの素材を活用します。」

EOL警告により停止した場合:
「{N}件の製品についてEOL・販売終了に関する情報がSharePointで確認されたため停止しました。`ai_generated/proposals/{案件名}/why_ctc_materials.md` にEOL警告情報を保存しました。提案内容を見直してから `/gaido-proposal-why-ctc {案件名}` を再実行してください。」

スキップした場合:
`.box/credentials.json` が存在する場合: 「SharePoint検索をスキップし、`ai_generated/proposals/{案件名}/why_ctc_materials.md` にガイダンスを保存しました（Box連携あり: Boxにもアップロード済み）。後から `/gaido-proposal-why-ctc {案件名}` を再実行することでSharePoint素材を補完できます。」
`.box/credentials.json` が存在しない場合: 「SharePoint検索をスキップし、`ai_generated/proposals/{案件名}/why_ctc_materials.md` にガイダンスを保存しました（Box未連携のためローカル保存。Box連携を有効にすると、この成果物が自動でBoxに保存されます。GAiDoアプリの Step 4 で設定できます）。後から `/gaido-proposal-why-ctc {案件名}` を再実行することでSharePoint素材を補完できます。」

## 注意事項

- access_token の有効期限が切れた場合、GAiDo デスクトップアプリが自動的にリフレッシュする（最大10分）。長時間セッションでも手動操作は不要
- Phase 1 探索はキーワード1つにつき上位15件、Phase 2 収集はキーワード1つにつき上位10件のみ処理する（時間短縮）
- Phase 1 で発見した語は **文書タイトル・抜粋に実際に出現した語** のみを採用し、知識から補完しない
- ダウンロードしたファイル（`/tmp/ms365_why_ctc_phase1/`, `/tmp/ms365_why_ctc_phase2/`）はセッション終了後に削除して構わない
- `why_ctc_materials.md` は提案ごとに上書きされる（再実行で更新可能）
