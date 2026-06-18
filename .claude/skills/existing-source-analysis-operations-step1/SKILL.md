---
name: existing-source-analysis-operations-step1
description: 既存ソース解析Step 1。ソースファイル一覧取得・todoファイル準備を行うWorker用スキル。
user-invocable: false
---

# Step 1: タスク準備（Worker用）

ソースファイル一覧を取得し、use-exclusive-todo-fileスキルのtodoファイルを準備する。

## 参照制約

解析対象は `output_system*/` 配下のソースコードのみ。

以下のディレクトリ・ファイルは**参照禁止**:
- `.claude/`
- `ai_generated/`（ただし `ai_generated/intermediate_files/from_source/` への出力は許可）
- `docs_with_ai/`
- `existing_docs/`

以下は**参照可能**:
- `output_system*/` 配下のすべてのファイル
- `ai_generated/intermediate_files/from_source/devops.md`（ローカル実行フェーズの出力。ビルド手順・URL等のヒントとして活用）

## 言語ルール

**すべての出力は日本語で記述すること。** コード例・変数名・型名はそのまま（英語のまま）でよいが、説明文は日本語。

## 前提

- **作業開始前に必ず `CLAUDE.md` を読み込むこと。** プロジェクト全体のルールを把握してから作業を開始する
- use-exclusive-todo-fileスキルのスクリプトパスとtodoファイルパスは、Leadからのspawnプロンプトで指定される
- このスキルを実行する前に `/use-exclusive-todo-file` スキルを読んでおくこと

## 処理手順

### 1. 出力ディレクトリ準備

```bash
mkdir -p ai_generated/intermediate_files/from_source/api_documents
mkdir -p ai_generated/intermediate_files/from_source/progress
```

### 2. 冪等チェック（再開判定）

開始前に `ai_generated/intermediate_files/from_source/` の状態を確認し、どのStepから再開するかを判定する。

```bash
echo "=== 冪等チェック ==="
HAS_README=$([ -f ai_generated/intermediate_files/from_source/README.md ] && echo 1 || echo 0)
HAS_ARCH=$([ -f ai_generated/intermediate_files/from_source/architecture.md ] && echo 1 || echo 0)
HAS_DB=$([ -f ai_generated/intermediate_files/from_source/db.md ] && echo 1 || echo 0)
HAS_SCREENS=$([ -f ai_generated/intermediate_files/from_source/screens.md ] && echo 1 || echo 0)
HAS_OPENAPI=$([ -f ai_generated/intermediate_files/from_source/openapi.yaml ] && echo 1 || echo 0)
HAS_FILESTRUCT=$([ -f ai_generated/intermediate_files/from_source/file_structure.md ] && echo 1 || echo 0)
HAS_APIDOCS=$([ -d ai_generated/intermediate_files/from_source/api_documents ] && [ "$(find ai_generated/intermediate_files/from_source/api_documents/ -type f 2>/dev/null | wc -l)" -gt 0 ] && echo 1 || echo 0)
HAS_TASKS=$([ -f ai_generated/intermediate_files/from_source/progress/source_file_tasks.md ] && echo 1 || echo 0)
echo "README.md=$HAS_README architecture.md=$HAS_ARCH db.md=$HAS_DB screens.md=$HAS_SCREENS openapi.yaml=$HAS_OPENAPI"
echo "file_structure.md=$HAS_FILESTRUCT api_documents=$HAS_APIDOCS source_file_tasks.md=$HAS_TASKS"
```

判定ルール（上から順に評価し、最初に一致した行を適用する）:

| # | 条件 | Leadへの報告 |
|---|------|------------|
| 1 | README.md が存在する | 「全完了スキップ」（全Step完了済み） |
| 2 | architecture.md + db.md + screens.md + openapi.yaml が全て存在する | 「Step 5から再開」 |
| 3 | file_structure.md が存在 + api_documents/ にファイルあり | 「Step 4から再開」 |
| 4 | source_file_tasks.md が存在する | 「Step 3から再開」とする（後続でコメント付与は行わないため todo の完了状態は不問） |
| 5 | 上記いずれにも該当しない | Step 2（ソースファイル一覧取得）へ進む |

Leadへの報告は上記の1文のみ（teamleadのコンテキスト保全のため）。判定#5の場合はLeadに報告せずStep 2に進む。

### 3. ソースファイル一覧取得

`output_system*/` 配下の全ソースファイルを取得する。**`| head` による件数制限は行わない（全ファイルを対象とする）。**

```bash
find output_system*/ -type f \
  -not -path '*/node_modules/*' \
  -not -path '*/.venv/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/vendor/*' \
  -not -name '*.lock' \
  -not -name 'package-lock.json' \
  -not -name 'yarn.lock'
```

### 4. 言語判定・todoファイル生成

Step 2の結果からソースコードファイル（`.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.java`, `.rs` 等）と主要設定ファイル（`package.json`, `tsconfig.json`, `Dockerfile`, `docker-compose.yml` 等）を抽出する。

言語判定:
- `.go` → Go
- `.ts`, `.tsx` → TypeScript
- `.js`, `.jsx` → JavaScript
- `.py` → Python
- `.java` → Java
- `.rs` → Rust
- 設定ファイル（`package.json`, `tsconfig.json`, `Dockerfile` 等）は「設定ファイル」カテゴリ

todoファイルの出力ディレクトリを作成:
```bash
mkdir -p ai_generated/intermediate_files/from_source/progress
```

抽出したファイルパスをuse-exclusive-todo-file.shの `init` コマンドに渡してtodoファイルを生成する。**AIがtodoファイルを直接書いてはならない。必ず `init` コマンド経由で作成すること。**

```bash
find output_system*/ -type f \
  -not -path '*/node_modules/*' \
  -not -path '*/.venv/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/vendor/*' \
  -not -name '*.lock' \
  -not -name 'package-lock.json' \
  -not -name 'yarn.lock' \
  -not -iname '*test*' \
  \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
     -o -name '*.py' -o -name '*.go' -o -name '*.java' -o -name '*.rs' \
     -o -name 'package.json' -o -name 'tsconfig.json' \
     -o -name 'Dockerfile' -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) \
  | xargs -I{} sh -c 'echo "$(wc -l < "$1" 2>/dev/null || echo 0) $1"' _ {} \
  | sort -n \
  | awk '{print $2}' \
  | <use-exclusive-todo-file.shのパス> init <todoファイル絶対パス>
```

### 5. 完了報告

Leadに「完了」をSendMessageで報告する。報告に含める内容:
- 生成したtodoファイルの総タスク数
- 検出した言語一覧
