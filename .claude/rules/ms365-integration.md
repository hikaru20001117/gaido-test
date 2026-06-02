# MS365 連携

`tools/ms365_client.py` を使ってSharePointの文書検索・ダウンロード・テキスト抽出が可能。
SharePointから社内資料を参照する必要がある場合は、このツールを積極的に活用すること。

## 認証情報

GAiDoアプリのSetup Wizardでシェアポイント連携を完了すると、認証情報が自動的に
`.ms365/credentials.json` に配置される（GAiDoホストの `~/.gaido/ms365/shared/` をコンテナに
bind mount したもの）。

```json
{
  "client_id": "...",
  "tenant_id": "...",
  "refresh_token": "...",
  "access_token": "...",
  "expires_at": 1748000000
}
```

- `access_token` と `expires_at` は GAiDo デスクトップアプリが Windows（準拠デバイス）から定期的にリフレッシュして書き込む
- `ms365_client.py` は `.ms365/credentials.json` の `access_token` を直接読んで使用する（コンテナ内でのリフレッシュは行わない）
- 認証情報が存在しない場合はMS365連携未設定を意味する → GAiDoアプリのSetup WizardでSharePoint連携を完了するようユーザーに案内すること

## CLIコマンド

```bash
# SharePoint文書をキーワード検索してテキスト抽出（上位5件）
python3 tools/ms365_client.py "クラウド移行 実績"

# 取得件数を指定
python3 tools/ms365_client.py "Cisco 導入事例" --top 20

# 出力先ディレクトリを指定
python3 tools/ms365_client.py "ゼロトラスト" --out-dir /tmp/search_results
```

## Pythonから使う場合

```python
from tools.ms365_client import MS365Client, TokenError, GraphAPIError

client = MS365Client()  # .ms365/credentials.json から自動的に access_token を取得

# 文書検索
try:
    hits = client.search_documents("クラウド移行 実績", top=10)
except TokenError as e:
    # 認証情報なし・期限切れ → Setup Wizard での再連携を案内
    print(f"認証エラー: {e}")
except GraphAPIError as e:
    print(f"APIエラー ({e.status_code}): {e}")

# 文書ダウンロード + テキスト抽出
from pathlib import Path
out_dir = Path("/tmp/ms365_results")
out_dir.mkdir(exist_ok=True)
for h in hits:
    res = h.get("resource", {})
    ref = res.get("parentReference", {})
    drive_id = ref.get("driveId")
    item_id = res.get("id")
    name = res.get("name", "")
    if drive_id and item_id:
        text = client.download_and_extract(drive_id, item_id, name, out_dir)
```

## 主なメソッド（MS365Client）

| メソッド | 用途 |
|---------|------|
| `load_token()` | トークンファイルを読み込み有効期限を確認（TokenError を送出） |
| `search_documents(query, top)` | Microsoft Graph Search API でSharePoint文書を検索 |
| `download_drive_item(drive_id, item_id, out_path)` | driveItem をバイナリダウンロード |
| `extract_text_from_file(file_path)` | PDF/PPTX/DOCX からテキスト抽出 |
| `download_and_extract(drive_id, item_id, filename, out_dir)` | ダウンロード+テキスト抽出を一括実行 |

## 対応テキスト抽出形式

| 拡張子 | 使用ライブラリ | 備考 |
|--------|--------------|------|
| `.pdf` | pdftotext (poppler-utils) | AI Agent コンテナにプリインストール済み |
| `.pptx` | python-pptx | `pip install python-pptx` が必要な場合あり |
| `.docx` | python-docx | `pip install python-docx` が必要な場合あり |

## エラーハンドリング

- **TokenError（認証情報なし）**: `.ms365/credentials.json` が存在しない → GAiDoアプリのSetup WizardでSharePoint連携を完了するようユーザーに案内する。`docker cp` は不要
- **TokenError（トークン期限切れ）**: `access_token` が期限切れ → GAiDo デスクトップアプリが自動的に更新する（最大10分）。解消しない場合はGAiDoアプリのSetup WizardでSharePoint連携を再実行するようユーザーに案内する
- **GraphAPIError (401)**: アクセストークンが無効 → 同上
- **GraphAPIError (403)**: アクセス権限なし → SharePoint上の共有設定を確認するようユーザーに伝える
