# Box連携

`tools/box_client.py` を使ってBoxのファイル取得・書き込み・アップロードが可能。
Boxに情報を読み書きする必要がある場合は、このツールを積極的に活用すること。

## 認証情報

`.box/credentials.json` に以下を保存：

```json
{
  "client_id": "...",
  "client_secret": "...",
  "refresh_token": "...",
  "base_folder_id": "0"
}
```

- `base_folder_id`: パス操作の起点フォルダID（企業Boxではルート `"0"` への書き込みが制限される場合があるため設定）
- 認証情報が存在しない場合はBox連携未設定を意味する → GAiDoアプリのStep 4で設定済みか確認すること
- refresh_tokenは60日未使用で失効する。失効した場合はStep4で再設定が必要

## CLIコマンド

```bash
# ファイルをアップロード（フォルダパス自動作成）
# 成功時に Box URL とアップロード先のフルパス（Box path:）を出力する
python3 tools/box_client.py upload <ファイルパス> --folder-path <Boxフォルダパス>

# ファイルをダウンロード（デフォルト保存先: ai_generated/input/）
python3 tools/box_client.py download <ファイルID> [--output <保存先パス>]

# フォルダを再帰的にダウンロード（フォルダID指定）
python3 tools/box_client.py download-folder <フォルダID> [--output-dir <保存先ディレクトリ>]

# フォルダを再帰的にダウンロード（パス指定）
python3 tools/box_client.py download-folder-by-path <フォルダパス> [--output-dir <保存先ディレクトリ>]

# フォルダ作成
python3 tools/box_client.py mkdir <フォルダ名> [--parent-id <ID>]

# フォルダ内一覧
python3 tools/box_client.py list [--folder-id <ID>]
```

## 成果物の自動アップロード方針

利用者向けの最終成果物を作成・更新したら、ユーザーの明示指示を待たずに毎回 Box へ自動アップロードすること（GAiDo の「人間の手離れが良いことを美徳とする」前提の具体化）。本方針は、専用スキルを介さずに直接作成した**アドホック成果物**を主対象とする。専用スキル（`gaido-proposal-*` / `gaido-estimate-pl-generator` / `gaido-persona-generator` / `project-advisor` / `gaido-deal-feedback` 等）が SKILL.md 内で既に自動アップロードを行う成果物は、スキルのフローを優先し、本方針で再アップロードしない（二重アップロード防止）。

### 何を上げるか（対象）

利用者・顧客が Box 上で確認・ダウンロードする最終納品物のみを対象とする。次のディレクトリに置かれた成果物が対象:

- `ai_generated/proposals/`（提案書 PPTX・QA一覧・リスク計画・why_ctc 素材 等）
- `ai_generated/project_plans/`（プロジェクト計画書 PPTX）
- `ai_generated/estimates/`（見積・PL Excel）
- `ai_generated/advisor/`（案件判定レポート・プロファイル・振り返り/分析レポート、`feedback/` 配下含む）
- `.claude/skills/personas/`（ペルソナ md。通常は `gaido-persona-generator` が自動アップロード済み）

### 何を上げないか（対象外）

- 中間/作業ファイル（生成途中・検討用。例: `*_draft.json` / `qa_draft.json` / `qa_review.md` / `contradictions.md` / `design_summary.md`）。ただし利用者に提示する最終サマリ（`reflection_summary.md` 等）はアップロード対象に含めてよい
- `ai_generated/requirements/` / `intermediate_files/` / `issues*` / `HANDOVER/`（開発内部・git 管理）
- `ai_generated/input/`（Box からのダウンロード入力先。逆流アップロード禁止）
- スクリーンショット類（`screenshots/` / `screens/` / `screen_detail.md` / `screen_design_phase/` / `pencil_screenshots/` / `readme_screenshots/`）
- `output_system/` 配下の実装コード（git 管理）、`gaido_progress.json` 等の UI ステートファイル
- **認証情報・機密**（`.box/credentials.json` / `.ms365/credentials.json` / refresh_token を含むファイル / `.env`）

### いつ・どう上げるか

1. 対象ディレクトリに最終成果物を生成・更新し終えた時点で、ユーザー指示を待たず直ちに実行する。
2. 発火するか否か（実行/スキップ）の判定は `.box/credentials.json` の**存在**を真偽源とする（存在＝実行、不在＝スキップして未連携通知）。なお、ファイルが存在しても refresh_token が失効している場合があり、これはアップロード実行時に `invalid_grant`（5項の失敗扱い）で検知される。
3. 実行コマンド:

   ```bash
   python3 tools/box_client.py upload <成果物パス> --folder-path "GAiDo/{案件名}/{用途}"
   ```

4. アップロード先フォルダパス（`--folder-path`）は次の規則で決める（フォルダ名を推測で作らない）:
   - ローカル `ai_generated/{用途}/{案件名}/...` → Box `GAiDo/{案件名}/{用途}`（既存スキルの `GAiDo/{案件名}/proposal` 等と同一規約）
   - 案件名が特定できないアドホック成果物は `GAiDo/adhoc/{YYYYMMDD}/` を既定の退避先とする
   - ペルソナは `GAiDo/personas/{カテゴリ}`
5. アップロード失敗（403/404/60日失効、50MB 超 等）でスキル・作業全体を止めない。失敗時はローカルパスを必ず案内し、「## エラーハンドリング」のリカバリ（権限確認・Step 4 での再設定）へ誘導する。

### credentials 未設定/失効時の挙動（サイレントスキップ禁止）

無言でローカル保存して終わってはならない。検知経路は2つある:

- **未設定（`.box/credentials.json` が存在しない）**: アップロード前にファイル存在で判定し、スキップする。
- **失効（ファイルは存在するが refresh_token が60日失効）**: アップロード実行時に `invalid_grant` で失敗する（5項参照）。

いずれの場合も、一度だけ簡潔に「Box 未連携のためローカルに保存しました。Box 連携を有効にすると、この成果物が自動で Box に保存されます（GAiDo アプリの Step 4 で設定できます）」と通知し、ローカル保存パスを案内すること（失効時は Step 4 での再設定を案内）。

### アップロード後の案内

アップロード成功後は、必ず次節「## アップロード後のパス案内（ハルシネーション防止）」に従い、`upload` が出力した `Box path:` 行の値をそのまま引用して保存先を伝える。`--folder-path` 文字列や `list` 出力からパスを推測してはならない。

### ドラフト・上書きの扱い

最終成果物は同名ファイルを上書きアップロードしてよい（最新版を Box に反映）。中間版・下書きは対象外。時系列保持が必要な成果物（振り返り/分析レポート等）は既存ファイルを削除・上書きせず追記/版管理する。

## アップロード後のパス案内（ハルシネーション防止）

`upload` コマンドは成功時に、アップロード先フォルダの**API検証済みフルパス**を
`Box path:` 行として出力する。これは Box API の `path_collection` から取得した
実際のパスであり、推測ではない。

```
アップロード完了: qa_list.xlsx
  Box URL: https://app.box.com/file/1234567890
  Box path: se4sd4-all > matsuguma > menicon_pos > qa
```

ユーザーにアップロード先を案内する際は、以下を厳守すること:

- **`Box path:` 行の値をそのまま引用する**（例:「Boxの `se4sd4-all > matsuguma > menicon_pos > qa` に保存しました」）
- `list` の出力やルートフォルダ名、`--folder-path` に渡した文字列から**パスを推測・組み立ててはならない**。`--folder-path` は `base_folder_id` を起点とする相対パスであり、ルートからの絶対パスとは一致しない
- `Box path:` が「(パス取得に失敗しました…)」の場合は、パスを推測せず、その旨をユーザーに伝えて Box URL で案内する

## Pythonから使う場合

```python
from tools.box_client import BoxClient

client = BoxClient()  # .box/credentials.json を読み込む

# アップロード（フォルダ自動作成）
client.upload_to_path("local/file.pdf", "GAiDo/案件名/proposal")

# ダウンロード（ファイルID指定）
path = client.download_file("12345678", output_path="ai_generated/input/file.pdf")

# フォルダをダウンロード
paths = client.download_folder("87654321", output_dir="ai_generated/input")

# フォルダ内一覧
items = client.list_items("87654321")
```

## 主なメソッド

| メソッド | 用途 |
|---------|------|
| `upload_to_path(local_path, box_folder_path)` | パス指定でアップロード（フォルダ自動作成） |
| `upload_file(local_path, folder_id)` | フォルダID指定でアップロード（50MB以下） |
| `download_file(file_id, output_path)` | ファイルIDでダウンロード |
| `download_folder(folder_id, output_dir)` | フォルダIDで再帰ダウンロード |
| `list_items(folder_id)` | フォルダ内アイテム一覧取得 |
| `create_folder(name, parent_id)` | フォルダ作成（同名既存時は既存を返す） |
| `ensure_folder_path(folder_path)` | パスを再帰的に作成しフォルダIDを返す |
| `resolve_folder_path(folder_path)` | パスからフォルダIDを解決（読み取り専用） |
| `describe_folder_path(folder_id)` | フォルダIDからAPI検証済みフルパス文字列を取得（推測なし。`Box path:` 出力に使用） |
| `get_folder_path_names(folder_id)` | フォルダIDからルート起点のフォルダ名リストを取得（`path_collection`使用） |

## エラーハンドリング

- **認証情報ファイルなし**: Box連携未設定のメッセージが出る。GAiDoアプリのStep 4で設定を促す
- **401**: 自動でトークンリフレッシュしてリトライする
- **403**: アクセス権限なし → Box上の共有設定を確認するようユーザーに伝える
- **404**: ファイル/フォルダIDが存在しない → IDが正しいか確認するようユーザーに伝える
- **60日失効**: `invalid_grant` エラー → GAiDoアプリのStep 4で再設定するようユーザーに伝える
