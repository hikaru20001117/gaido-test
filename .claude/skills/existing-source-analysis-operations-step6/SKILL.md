---
name: existing-source-analysis-operations-step6
description: 既存ソース解析Step 6。README.md生成・コミット＆プッシュ・返却サマリ作成を行うWorker用スキル。
user-invocable: false
---

# Step 6: README.md生成・コミット・返却サマリ（Worker用）

全ステップの成果物を踏まえて、README.mdの生成、gitコミット＆プッシュ、返却サマリの作成を行う。

## 参照制約

解析対象は `ai_generated/intermediate_files/from_source/` 配下の成果物。

以下のディレクトリ・ファイルは**参照禁止**:
- `.claude/`
- `docs_with_ai/`
- `existing_docs/`
- `ai_generated/intermediate_files/from_docs/`

## 言語ルール

**すべての出力は日本語で記述すること。** コード例・変数名・型名はそのまま（英語のまま）でよいが、説明文は日本語。

## 前提作業

**作業開始前に必ず `CLAUDE.md` を読み込むこと。** プロジェクト全体のルール（mermaid記法の使用、コミットメッセージ形式等）を把握してから作業を開始する。

## 処理手順

### 1. README.md生成

`ai_generated/intermediate_files/from_source/` 配下の全成果物を読み取り、`ai_generated/intermediate_files/from_source/README.md` を生成する。

README.mdには以下を含める（日本語で記述すること）:
- 生成されたファイルの一覧と概要
- どんな時にどのファイルを読めばいいかのガイド
- 検出した技術スタックの概要

### 2. 完了条件の確認

以下の完了条件を確認する:

```bash
echo "=== 完了条件チェック ==="

# 必須ファイルの存在
for f in README.md file_structure.md db.md screens.md architecture.md openapi.yaml; do
  if [ -f "ai_generated/intermediate_files/from_source/$f" ]; then
    echo "OK: $f"
  else
    echo "NG: $f が存在しない"
  fi
done

# APIドキュメント
API_COUNT=$(find ai_generated/intermediate_files/from_source/api_documents/ -type f 2>/dev/null | wc -l)
echo "APIドキュメント: ${API_COUNT}件"

# AUTO_GENERATEDコメント
COMMENT_FILES=$(grep -rl "AUTO_GENERATED:" output_system*/ 2>/dev/null | wc -l)
echo "AUTO_GENERATED付きファイル: ${COMMENT_FILES}件"
```

### 3. コミット＆プッシュ

生成した中間ファイルをコミット＆プッシュする（`.claude/rules/git-rules.md` に従う）。

```bash
git add ai_generated/intermediate_files/from_source/
git commit -m "docs(analysis): Add source analysis intermediate files

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

### 4. 返却サマリ作成

Leadに以下の返却サマリをSendMessageで送信する。Leadはこの内容をそのまま表示する。

```
## 既存ソース解析 完了レポート

### 生成ファイル一覧
- file_structure.md: {行数}行
- db.md: {行数}行
- screens.md: {行数}行
- architecture.md: {行数}行
- openapi.yaml: {行数}行
- api_documents/: {ファイル数}件
- README.md: {行数}行

### 技術スタック
{検出した言語・フレームワーク}

### コメント付与結果
- AUTO_GENERATED付きファイル: {件数}件
- source_file_tasks.md 完了率: {完了数}/{総数}

### 検証結果サマリ
- Step 3 コメント関連検証: {合格/不合格}
- Step 5 全体検証: {合格/不合格}

### gitコミット
- コミット済み: {はい/いいえ}
```
