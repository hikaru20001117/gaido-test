---
name: existing-source-analysis-operations-step5
description: 既存ソース解析Step 5。専門分析の成果物を含む全体検証（日本語・必須ファイル・mermaid確認）を行うWorker用スキル。
user-invocable: false
---

# Step 5: 全体検証（Worker用）

専門分析（Step 4）完了後の全成果物に対する品質検証を行う。

## 参照制約

解析対象は `output_system*/` 配下のソースコードと `ai_generated/intermediate_files/from_source/` 配下の成果物。

以下のディレクトリ・ファイルは**参照禁止**:
- `.claude/`
- `docs_with_ai/`
- `existing_docs/`
- `ai_generated/intermediate_files/from_docs/`

## 言語ルール

**すべての出力は日本語で記述すること。** コード例・変数名・型名はそのまま（英語のまま）でよいが、説明文は日本語。

## 前提作業

**作業開始前に必ず `CLAUDE.md` を読み込むこと。** プロジェクト全体のルール（mermaid記法の使用等）を把握してから作業を開始する。

## 処理手順

### 1. 検証1: 日本語出力ルール

各ファイルの先頭部分を読み取り、説明文が日本語で書かれていることを確認する。英語の説明文が含まれている場合は、該当ファイルを日本語に書き直す。

```bash
for f in ai_generated/intermediate_files/from_source/*.md ai_generated/intermediate_files/from_source/*.yaml; do
  echo "=== $(basename $f) ==="
  head -20 "$f" 2>/dev/null
  echo ""
done
```

**不合格の場合**: 該当ファイルを直接Editツールで日本語に修正する。

### 2. 検証3: 必須ファイルの存在確認

```bash
for f in file_structure.md db.md screens.md architecture.md openapi.yaml; do
  if [ -f "ai_generated/intermediate_files/from_source/$f" ]; then
    echo "OK: $f ($(wc -l < ai_generated/intermediate_files/from_source/$f) 行)"
  else
    echo "NG: $f が存在しない"
  fi
done
```

**不合格の場合**: 欠落しているファイルに応じて、Leadに「Step Nからやり直し」とだけ報告する。
- file_structure.md が欠落 → 「Step 3からやり直し」
- db.md / screens.md / architecture.md / openapi.yaml が欠落 → 「Step 4からやり直し」

### 3. 検証4: mermaid記法の使用確認

```bash
for f in db.md screens.md architecture.md; do
  COUNT=$(grep -c '```mermaid' "ai_generated/intermediate_files/from_source/$f" 2>/dev/null || echo 0)
  echo "$f: mermaidブロック ${COUNT}件"
done
```

mermaidブロックが0件のファイルがあれば、該当ファイルに適切なmermaid図を追加する。

### 4. 完了報告

検証が全て合格の場合、Leadに「完了」をSendMessageで報告する。報告は最低限の情報のみ:
- 「完了」または「Step Nからやり直し」の1文のみ（teamleadのコンテキスト保全のため）
