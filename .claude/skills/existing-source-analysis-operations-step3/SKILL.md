---
name: existing-source-analysis-operations-step3
description: 既存ソース解析Step 3。APIドキュメント生成・file_structure.md生成を行うWorker用スキル。
user-invocable: false
---

# Step 3: 後処理（Worker用）

ソースコードに対して、APIドキュメント生成と file_structure.md 生成を行う。

## 参照制約

解析対象は `output_system*/` 配下のソースコードのみ。

以下のディレクトリ・ファイルは**参照禁止**:
- `.claude/`
- `ai_generated/`（ただし `ai_generated/intermediate_files/from_source/` への出力は許可）
- `docs_with_ai/`
- `existing_docs/`

## 言語ルール

**すべての出力は日本語で記述すること。** コード例・変数名・型名はそのまま（英語のまま）でよいが、説明文は日本語。

## 処理手順

### 1. APIドキュメント生成

ソースコードに対して、**言語ごとのドキュメント化ツール（xDoc系）** でAPIドキュメントを生成する。AIによるマークダウン手書きで代替してはならない（フォールバック条件を満たした場合のみ許可）。

#### 1a: 言語検出

```bash
ls output_system*/package.json 2>/dev/null && echo "LANG: typescript"
ls output_system*/go.mod 2>/dev/null && echo "LANG: go"
ls output_system*/requirements.txt output_system*/pyproject.toml output_system*/setup.py 2>/dev/null && echo "LANG: python"
ls output_system*/Cargo.toml 2>/dev/null && echo "LANG: rust"
ls output_system*/pom.xml output_system*/build.gradle 2>/dev/null && echo "LANG: java"
```

#### 1b: ドキュメントツールインストール

**方式A: マークダウン直接出力が可能な言語**

| 言語 | ツール | インストールコマンド | 参考URL |
|------|--------|-------------------|---------|
| TypeScript/JavaScript | TypeDoc + typedoc-plugin-markdown | `cd output_system* && npm install --save-dev typedoc typedoc-plugin-markdown` | https://github.com/typedoc2md/typedoc-plugin-markdown |
| Go | gomarkdoc | `go install github.com/princjef/gomarkdoc/cmd/gomarkdoc@latest && export PATH=$PATH:$(go env GOPATH)/bin` | https://github.com/princjef/gomarkdoc |
| Python | pydoc-markdown | `pip install pydoc-markdown` | https://github.com/NiklasRosenstein/pydoc-markdown |

**方式B: HTML出力 → pandocでマークダウン変換が必要な言語**

| 言語 | ドキュメントツール | pandocインストール |
|------|-----------------|-------------------|
| Java | Javadoc（JDK同梱） | `apt-get install -y pandoc` |
| Rust | rustdoc（標準ツール） | `apt-get install -y pandoc` |
| その他 | 各言語の標準ドキュメントツール | `apt-get install -y pandoc` |

pandoc参考URL: https://github.com/jgm/pandoc

#### 1c: ツール実行

```bash
mkdir -p ai_generated/intermediate_files/from_source/api_documents
```

**方式A: マークダウン直接出力**

| 言語 | 実行コマンド例 |
|------|--------------|
| TypeScript | `cd output_system* && npx typedoc --plugin typedoc-plugin-markdown --out ../ai_generated/intermediate_files/from_source/api_documents/typescript/ --entryPointStrategy expand src/` |
| Go | `cd output_system* && gomarkdoc --output ../ai_generated/intermediate_files/from_source/api_documents/go/godoc.md ./...` |
| Python | `cd output_system* && pydoc-markdown -I . -m <モジュール名> --render-toc > ../ai_generated/intermediate_files/from_source/api_documents/python/api.md` |

**方式B: HTML出力 → pandoc変換**

```bash
# 例: Javadoc → マークダウン
cd output_system*
mkdir -p /tmp/javadoc_html
javadoc -d /tmp/javadoc_html -sourcepath src -subpackages .
mkdir -p ../ai_generated/intermediate_files/from_source/api_documents/java
find /tmp/javadoc_html -name "*.html" | while read f; do
  BASENAME=$(basename "${f%.html}")
  pandoc -f html -t gfm "$f" -o "../ai_generated/intermediate_files/from_source/api_documents/java/${BASENAME}.md"
done
rm -rf /tmp/javadoc_html
```

上記はコマンド例であり、プロジェクト構成に応じてパスやオプションを調整すること。

#### 1d: 検証・フォールバック

```bash
TOOL_OUTPUT_COUNT=$(find ai_generated/intermediate_files/from_source/api_documents/ -type f 2>/dev/null | wc -l)
echo "ツール出力ファイル数: $TOOL_OUTPUT_COUNT"
```

- `TOOL_OUTPUT_COUNT >= 1` → ツール出力成功。次の手順（file_structure.md生成）へ進む
- `TOOL_OUTPUT_COUNT == 0` → ツール実行に失敗。以下のフォールバックを許可:
  - AIがソースコードを読み取ってマークダウン形式のAPIドキュメントを生成してよい
  - 出力ファイルの先頭に `<!-- FALLBACK: ドキュメント生成ツール実行失敗のためAI生成 -->` を記載すること
  - フォールバック理由（エラーメッセージ等）をファイル内に記録すること

### 2. file_structure.md生成

ソースコード全体を読み取り、以下の内容で `ai_generated/intermediate_files/from_source/file_structure.md` を生成する。

- ディレクトリ構成（ツリー形式）
- 各ディレクトリ・ファイルの役割（テーブル形式）
- npmスクリプト等のビルドコマンド一覧
- ファイル間の呼び出し関係

ソースコードから読み取れた事実のみを記載。推測は「推測:」と明記する。

### 3. 完了報告

Leadに「完了」をSendMessageで報告する。報告は最低限の情報のみ（「完了」の1文）。

## others.mdへの追記

自分の担当外だが記録すべき情報を見つけた場合、`ai_generated/intermediate_files/from_source/others.md` に追記する。追記のみ許可、既存内容の編集は禁止。
