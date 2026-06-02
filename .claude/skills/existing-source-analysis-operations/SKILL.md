---
name: existing-source-analysis-operations
description: 既存ソース解析の手順。オーケストレーター（メインAgent）が読むスキル。ステップごとにSubAgentをspawnし、処理を委任する。
user-invocable: false
---

# 既存ソース解析手順（オーケストレーター用）

ソースコードのみを解析し、requirements形式の中間ファイルを `ai_generated/intermediate_files/from_source/` に生成する。

> **最重要ルール（3つとも厳守）:**
> 1. **あなた（オーケストレーター）は処理の実態を行わない。** Editツール・sedコマンド等でソースファイルや成果物ファイルを変更してはならない。あなたが行うのはSubAgent起動・完了確認のみ。**例外: Step 2ではcomment-orchestrator.shをBash toolで起動する。**
> 2. **todoファイルを直接読んだり書いたりしないこと。** todoファイルの操作は `use-exclusive-todo-file` スキルを通して行うこと。ReadやEditでtodoファイルを操作すると、排他制御が効かずタスクの重複取得やステータス不整合が発生する。
> 3. **Step 2のコメント付与はSubAgentではなくcomment-orchestrator.shで実行する。** SubAgentを直接spawnしてはならない。

## 定数

| 名前 | 値 |
|------|-----|
| todoファイル絶対パス | `ai_generated/intermediate_files/from_source/progress/source_file_tasks.md` |
| use-exclusive-todo-fileスクリプトパス | `.claude/skills/use-exclusive-todo-file/scripts/use-exclusive-todo-file.sh` |

## 出力ファイル一覧

| ファイル | 担当Step | 内容 |
|---------|---------|------|
| `file_structure.md` | Step 3 | ディレクトリ・ファイル一覧と概要 |
| `api_documents/` | Step 3 | TSDoc/PyDoc等によるAPIドキュメント |
| `db.md` | Step 4 | データベースER図（型情報込み） |
| `screens.md` | Step 4 | 画面遷移図（WebシステムならURL込み） |
| `architecture.md` | Step 4 | アーキテクチャ |
| `openapi.yaml` | Step 4 | WebAPI定義（OpenAPI形式） |
| `others.md` | 各Step共有 | 上記に該当しない情報の受け皿（追記のみ） |
| `README.md` | Step 6 | どんな時に何ファイルを読めばいいかのガイド |
| `devops.md` | ローカル実行フェーズ | ビルド・デプロイ構成（本フェーズでは生成しない） |

各ファイルの内容は、ソースコードから読み取れた事実のみを記載すること。推測は「推測:」と明記する。

## SubAgent spawn共通ルール

SubAgentをspawnする際、Agent toolに以下のパラメータを必ず指定すること:

```
model: "sonnet"
run_in_background: true
```

**nameパラメータは指定しないこと。** nameを指定するとTeammateになってしまう。省略することでSubAgentとして起動される。

理由: Step 1-6はすべてスキルに手順が詳細に書かれた定型作業であり、Opusの推論力は不要。コスト削減のため全SubAgentをSonnetで動かす。

## Step 1: タスク準備

1. 以下の設定でSubAgent 1名をspawnする

| Agent toolパラメータ | 値 |
|---------------------|-----|
| model | `"sonnet"` |
| run\_in\_background | `true` |
| prompt | 下記のspawnプロンプト |

```
まずCLAUDE.mdと.claude/rules/配下の全ルールファイルを読んでください。次に`/use-exclusive-todo-file` スキルを読んでから、`/existing-source-analysis-operations-step1` スキルの手順に従ってください。
スクリプトパス: .claude/skills/use-exclusive-todo-file/scripts/use-exclusive-todo-file.sh
todoファイル: ai_generated/intermediate_files/from_source/progress/source_file_tasks.md
```

2. SubAgentの完了を待ち、戻り値に従って該当Stepに進む:
  - 「完了」→ Step 2へ
  - 「Step Nから再開」→ 該当Stepへ
  - 「全完了スキップ」→ 処理終了（全Step完了済み）

## Step 2: コメント付与（comment-orchestrator.sh）

1. comment-orchestrator.shをBash toolで実行する（`run_in_background: true`）

```bash
bash .claude/skills/existing-source-analysis-operations/scripts/comment-orchestrator.sh \
  5 \
  ai_generated/intermediate_files/from_source/progress/source_file_tasks.md \
  .claude/skills/existing-source-analysis-operations-step2/SKILL.md \
  3
```

引数: `<N=5> <todoファイルパス> <コメントルールファイルパス> <MAX_ROUNDS=3>`

2. 完了通知を受け取り、終了コードで判断する:
   - 終了コード0（全完了）: ログ集計SubAgentをspawnし（下記参照）、Step 3へ
   - 終了コード1（MAX_ROUNDSラウンド経過しても未完了）: ユーザーに報告して中断
   - 終了コード2（設定エラー）: ユーザーに報告して中断

3. ログ集計SubAgentをspawnする

| Agent toolパラメータ | 値 |
|---------------------|-----|
| model | `"sonnet"` |
| run\_in\_background | `true` |
| prompt | 下記のspawnプロンプト |

```
ワーカーログを集計してサマリレポートを生成してください。

ログファイル: ai_generated/intermediate_files/from_source/progress/comment_writer_*.log
todoファイル: ai_generated/intermediate_files/from_source/progress/source_file_tasks.md
出力先: ai_generated/intermediate_files/from_source/progress/step2_summary.md

集計内容:
1. 全体サマリ（総ファイル数、成功数[x]、失敗数[!]、未処理数[ ]、総コスト、総処理時間）
2. ワーカー別サマリ（テーブル形式: ワーカーID、処理ファイル数、成功数、失敗数、稼働時間、終了理由）
3. 失敗ファイル一覧（[!]状態のファイルと失敗理由）
4. 異常検知（編集なし完了DONE_NO_CHANGEのファイル一覧、コストが異常に高いファイル）

完了したらサマリの内容を返してください。
```

4. ログ集計SubAgentの返却サマリを受け取る（内容をそのまま保持。Step 3に渡す情報として使用）

## Step 3: 後処理（検証・APIドキュメント・file_structure.md）

1. 以下の設定でSubAgent 1名をspawnする

| Agent toolパラメータ | 値 |
|---------------------|-----|
| model | `"sonnet"` |
| run\_in\_background | `true` |
| prompt | 下記のspawnプロンプト |

```
まずCLAUDE.mdと.claude/rules/配下の全ルールファイルを読んでください。次に`/existing-source-analysis-operations-step3` スキルの手順に従ってください。
todoファイル: ai_generated/intermediate_files/from_source/progress/source_file_tasks.md
```

2. SubAgentの完了を待ち、戻り値に従う:
  - 「完了」→ Step 4へ
  - 「Step 2からやり直し」→ Step 2に戻る

## Step 4: 専門分析（並列処理）

まず、既に生成済みのファイルを確認し、未生成の分析のみ実行する。

```bash
for f in architecture.md:existing-source-analysis-architecture-operations db.md:existing-source-analysis-db-operations openapi.yaml:existing-source-analysis-openapi-operations screens.md:existing-source-analysis-screens-operations; do
  FILE="${f%%:*}"
  SKILL="${f##*:}"
  if [ -f "ai_generated/intermediate_files/from_source/$FILE" ]; then
    echo "SKIP: $FILE（既に存在） → $SKILL をスキップ"
  else
    echo "TODO: $FILE → $SKILL を実行"
  fi
done
```

- 全ファイルが存在する場合: Step 4をスキップし、Step 5に進む
- 未生成のものがある場合: 未生成の分析ごとにSubAgentをspawnする

各SubAgentは以下の設定でspawnする:

| Agent toolパラメータ | 値 |
|---------------------|-----|
| model | `"sonnet"` |
| run\_in\_background | `true` |
| prompt | 下表のspawnプロンプト |

| 成果物 | spawnプロンプト |
|--------|---------------|
| architecture.md | まずCLAUDE.mdと.claude/rules/配下の全ルールファイルを読んでください。次に `ai_generated/intermediate_files/from_source/file_structure.md` と `ai_generated/intermediate_files/from_source/api_documents/` 配下の主要ファイルを読んでください。その後 `/existing-source-analysis-architecture-operations` スキルの手順に従ってください。担当外だが記録すべき情報は `ai_generated/intermediate_files/from_source/others.md` に追記してください（追記のみ、既存内容の編集禁止）。すべての出力は日本語で記述してください。 |
| db.md | （同上のCLAUDE.md+rules読み込み指示 + 事前準備指示 +） `/existing-source-analysis-db-operations` スキルの手順に従ってください。（同上のothers.md追記指示・日本語指示） |
| openapi.yaml | （同上のCLAUDE.md+rules読み込み指示 + 事前準備指示 +） `/existing-source-analysis-openapi-operations` スキルの手順に従ってください。（同上のothers.md追記指示・日本語指示） |
| screens.md | （同上のCLAUDE.md+rules読み込み指示 + 事前準備指示 +） `/existing-source-analysis-screens-operations` スキルの手順に従ってください。（同上のothers.md追記指示・日本語指示） |

全SubAgentの完了を待つ。

## Step 5: 全体検証

1. 以下の設定でSubAgent 1名をspawnする

| Agent toolパラメータ | 値 |
|---------------------|-----|
| model | `"sonnet"` |
| run\_in\_background | `true` |
| prompt | 下記のspawnプロンプト |

```
まずCLAUDE.mdと.claude/rules/配下の全ルールファイルを読んでください。次に`/existing-source-analysis-operations-step5` スキルの手順に従ってください。
```

2. SubAgentの完了を待ち、戻り値に従う:
  - 「完了」→ Step 6へ
  - 「Step Nからやり直し」→ 該当Stepに戻る

## Step 6: README.md生成・コミット・返却サマリ

1. 以下の設定でSubAgent 1名をspawnする

| Agent toolパラメータ | 値 |
|---------------------|-----|
| model | `"sonnet"` |
| run\_in\_background | `true` |
| prompt | 下記のspawnプロンプト |

```
まずCLAUDE.mdと.claude/rules/配下の全ルールファイルを読んでください。次に`/existing-source-analysis-operations-step6` スキルの手順に従ってください。
```

2. SubAgentから返却サマリを受け取ったら、その内容をそのまま表示する。

## 省略モード（コメント付与スキップ）

メインAgentから「コメント付与をスキップ」の指示がある場合、以下の手順で実行する:

- Step 1（タスク準備）: スキップ
- Step 2（コメント付与）: スキップ
- Step 3（後処理）: file_structure.md生成のみ実行。spawnプロンプトに「コメント付与率検証とAPIドキュメント生成はスキップし、file_structure.md生成のみ実行してください」と追記する
- Step 4（専門分析）: 通常通り実行
- Step 5（全体検証）: 通常通り実行
- Step 6（README.md生成・コミット・返却サマリ）: 通常通り実行
