---
name: existing-source-analysis-operations-step3
description: 既存ソース解析Step 3。コメント付与率検証・APIドキュメント生成・file_structure.md生成を行うWorker用スキル。
user-invocable: false
---

# Step 3: 後処理（Worker用）

コメント付与済みのソースコードに対して、検証・APIドキュメント生成・file_structure.md生成を行う。

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

### 1. コメント付与率検証

#### 検証A: ファイルカバレッジ確認

```bash
TOTAL=$(grep -c '^\- \[' ai_generated/intermediate_files/from_source/progress/source_file_tasks.md)
DONE=$(grep -c -E '^\- \[[x!]\]' ai_generated/intermediate_files/from_source/progress/source_file_tasks.md)
TODO=$(grep -c '^\- \[ \]' ai_generated/intermediate_files/from_source/progress/source_file_tasks.md)
echo "ファイルカバレッジ: ${DONE}/${TOTAL} 完了（[!]含む）, ${TODO} 未完了"
```

- 完了率100%: 検証Bに進む
- 未完了あり: オーケストレーターに「未完了ファイルあり」を報告する（オーケストレーターがreset-doing→追加Workerで再処理する）

#### 検証B: 関数カバレッジ確認（サンプリング）

言語ごとにランダムに5ファイルを選択し、公開関数・メソッド数とドキュメントコメント数を比較する。

```bash
# TypeScriptの場合
echo "=== TypeScript サンプリング検証 ==="
for FILE in $(grep '^\- \[x\].*\.tsx\?$' ai_generated/intermediate_files/from_source/progress/source_file_tasks.md | sed 's/^- \[x\] //' | shuf | head -5); do
  FUNC_COUNT=$(grep -cE 'export (function|const|class)' "$FILE" 2>/dev/null || echo 0)
  PARAM_COUNT=$(grep -c '@param' "$FILE" 2>/dev/null || echo 0)
  AUTO_COUNT=$(grep -c 'AUTO_GENERATED' "$FILE" 2>/dev/null || echo 0)
  echo "$FILE: 公開関数 $FUNC_COUNT, @param $PARAM_COUNT, AUTO_GENERATED $AUTO_COUNT"
done

# Goの場合
echo "=== Go サンプリング検証 ==="
for FILE in $(grep '^\- \[x\].*\.go$' ai_generated/intermediate_files/from_source/progress/source_file_tasks.md | sed 's/^- \[x\] //' | shuf | head -5); do
  FUNC_COUNT=$(grep -c '^func ' "$FILE" 2>/dev/null || echo 0)
  AUTO_COUNT=$(grep -c 'AUTO_GENERATED' "$FILE" 2>/dev/null || echo 0)
  echo "$FILE: 関数定義 $FUNC_COUNT, AUTO_GENERATED $AUTO_COUNT"
done
```

- 各ファイルでAUTO_GENERATEDコメント数が関数定義数の50%以上: 合格
- 50%未満のファイルがあれば、そのファイルを個別に再処理する（Editツールで直接コメントを追加）

#### 検証C: フォーマット品質確認

```bash
echo "=== フォーマット品質（全体） ==="
TS_PARAM=$(grep -r '@param' output_system*/ --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
TS_RETURNS=$(grep -r '@returns' output_system*/ --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
GO_AUTO=$(grep -r 'AUTO_GENERATED' output_system*/ --include='*.go' 2>/dev/null | wc -l)
echo "TypeScript: @param ${TS_PARAM}件, @returns ${TS_RETURNS}件"
echo "Go: AUTO_GENERATED ${GO_AUTO}件"
```

- TypeScript: @param が10件以上 → 合格
- @param が0件のファイル（検証Bのサンプル中）があれば、完了レポートに記載

**検証で不合格の場合**: 不合格のファイルを直接修正する（Editツール使用）。全ファイルの修正は不要だが、不足の傾向と原因を完了レポートに記載する。

### 2. APIドキュメント生成

コメント付与済みのソースコードに対して、**言語ごとのドキュメント化ツール（xDoc系）** でAPIドキュメントを生成する。AIによるマークダウン手書きで代替してはならない（フォールバック条件を満たした場合のみ許可）。

#### 2a: 言語検出

```bash
ls output_system*/package.json 2>/dev/null && echo "LANG: typescript"
ls output_system*/go.mod 2>/dev/null && echo "LANG: go"
ls output_system*/requirements.txt output_system*/pyproject.toml output_system*/setup.py 2>/dev/null && echo "LANG: python"
ls output_system*/Cargo.toml 2>/dev/null && echo "LANG: rust"
ls output_system*/pom.xml output_system*/build.gradle 2>/dev/null && echo "LANG: java"
```

#### 2b: ドキュメントツールインストール

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

#### 2c: ツール実行

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

#### 2d: 検証・フォールバック

```bash
TOOL_OUTPUT_COUNT=$(find ai_generated/intermediate_files/from_source/api_documents/ -type f 2>/dev/null | wc -l)
echo "ツール出力ファイル数: $TOOL_OUTPUT_COUNT"
```

- `TOOL_OUTPUT_COUNT >= 1` → ツール出力成功。Step 3に進む
- `TOOL_OUTPUT_COUNT == 0` → ツール実行に失敗。以下のフォールバックを許可:
  - AIがソースコードを読み取ってマークダウン形式のAPIドキュメントを生成してよい
  - 出力ファイルの先頭に `<!-- FALLBACK: ドキュメント生成ツール実行失敗のためAI生成 -->` を記載すること
  - フォールバック理由（エラーメッセージ等）をファイル内に記録すること

### 3. file_structure.md生成

コメント付与済みのソースコード全体を読み取り、以下の内容で `ai_generated/intermediate_files/from_source/file_structure.md` を生成する。

- ディレクトリ構成（ツリー形式）
- 各ディレクトリ・ファイルの役割（テーブル形式）
- npmスクリプト等のビルドコマンド一覧
- ファイル間の呼び出し関係

ソースコードから読み取れた事実のみを記載。推測は「推測:」と明記する。

### 4. コメント関連の品質検証

Step 1〜3の成果物（コメント付与済みソースコード、APIドキュメント）に対する品質検証を行う。

#### 検証2: APIドキュメントがツール出力であること

```bash
find ai_generated/intermediate_files/from_source/api_documents/ -type f 2>/dev/null
grep -rl "FALLBACK" ai_generated/intermediate_files/from_source/api_documents/ 2>/dev/null
```

- ツール出力ファイルが存在すること
- FALLBACKファイルがある場合は、フォールバック理由が妥当か確認する

#### 検証5: AUTO_GENERATEDコメントの確認

```bash
COMMENT_COUNT=$(grep -rl "AUTO_GENERATED:" output_system*/ 2>/dev/null | wc -l)
echo "AUTO_GENERATED: コメント追加ファイル数: $COMMENT_COUNT"
```

#### 検証6: 関数レベルのドキュメントコメント品質（80%基準）

```bash
echo "=== TypeScript: TSDoc形式コメント ==="
TS_PARAM=$(grep -r '@param' output_system*/ --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
TS_RETURNS=$(grep -r '@returns' output_system*/ --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
TS_AUTODOC=$(grep -r 'AUTO_GENERATED' output_system*/ --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
echo "@param: ${TS_PARAM}件, @returns: ${TS_RETURNS}件, AUTO_GENERATED: ${TS_AUTODOC}件"

echo "=== Go: GoDoc形式コメント ==="
GO_FUNC_TOTAL=$(grep -r '^func ' output_system*/ --include='*.go' 2>/dev/null | wc -l)
GO_AUTODOC=$(grep -r 'AUTO_GENERATED:' output_system*/ --include='*.go' 2>/dev/null | wc -l)
echo "関数定義: ${GO_FUNC_TOTAL}件, AUTO_GENERATEDコメント: ${GO_AUTODOC}件"
```

**合格基準:**
- TypeScript: `@param` 件数が公開関数数の80%以上
- Go: AUTO_GENERATEDコメント数 + 既存GoDocコメント数が関数定義数の80%以上
- `source_file_tasks.md` の完了率が100%であること

#### 検証7: 既存英語コメントの扱い

```bash
grep -r '^// ' output_system*/ --include='*.go' | grep -v AUTO_GENERATED | head -5
```

既存コメントは「変更禁止」ルールがあるため、英語のままでよい。この事実を完了報告に含める。

#### 検証8: AUTO_GENERATED:ブロックコメント形式の確認

1つのコメントブロック内に `AUTO_GENERATED:` が複数回出現していないか確認する。

```bash
echo "=== TypeScript: ブロックコメント内AUTO_GENERATED:重複チェック ==="
awk '/\/\*\*/{block=$0"\n";inblock=1;next} inblock{block=block$0"\n"} inblock&&/\*\//{inblock=0;n=gsub(/AUTO_GENERATED:/,"&",block);if(n>=2)print "重複("n"回):\n"block"---";block=""}' output_system*/**/*.ts output_system*/**/*.tsx 2>/dev/null | head -20
echo ""
echo "=== Go: コメントブロック内AUTO_GENERATED:重複チェック ==="
awk '/^\/\// {block=block $0 "\n"; next} {if(block!=""){n=gsub(/AUTO_GENERATED:/,"&",block); if(n>=2) print "重複("n"回):\n" block "---"; block=""}} END{if(block!=""){n=gsub(/AUTO_GENERATED:/,"&",block); if(n>=2) print "重複("n"回):\n" block "---"}}' output_system*/**/*.go 2>/dev/null | head -20
```

**合格基準:** 重複が0件であること。
**不合格の場合:** 該当ファイルを直接修正する。1つのブロックコメントにつき `AUTO_GENERATED:` は先頭行に1回だけにし、`@param`/`@returns`/引数・返り値の行からは `AUTO_GENERATED:` を除去する。

#### 品質判定

検証6が不合格の場合:
1. `source_file_tasks.md` で `[x]` のファイルのうち `@param` も `引数:` もないファイルを未完了に戻す:
```bash
while IFS= read -r line; do
  FILE=$(echo "$line" | sed 's/^- \[x\] //')
  if [ -f "$FILE" ]; then
    HAS_PARAM=$(grep -c '@param\|引数:' "$FILE" 2>/dev/null || echo 0)
    if [ "$HAS_PARAM" -eq 0 ]; then
      echo "関数レベルコメント不足: $FILE → 未完了に戻す"
      sed -i "s|^\- \[x\] ${FILE}$|- [ ] ${FILE}|" ai_generated/intermediate_files/from_source/progress/source_file_tasks.md
    fi
  fi
done < <(grep '^\- \[x\]' ai_generated/intermediate_files/from_source/progress/source_file_tasks.md)
```
2. `file_structure.md` と `api_documents/` を削除する（コメント追加後に再生成が必要なため）:
```bash
rm -f ai_generated/intermediate_files/from_source/file_structure.md
rm -rf ai_generated/intermediate_files/from_source/api_documents/
mkdir -p ai_generated/intermediate_files/from_source/api_documents
```
3. Leadに「Step 2からやり直し」とだけ報告する（詳細は報告しない。teamleadのコンテキスト保全のため）

### 5. 完了報告

検証が全て合格の場合、Leadに「完了」をSendMessageで報告する。報告は最低限の情報のみ:
- 「完了」または「Step 2からやり直し」の1文のみ

## others.mdへの追記

自分の担当外だが記録すべき情報を見つけた場合、`ai_generated/intermediate_files/from_source/others.md` に追記する。追記のみ許可、既存内容の編集は禁止。
