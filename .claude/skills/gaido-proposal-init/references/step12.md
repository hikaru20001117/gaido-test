# Step 12: 残成果物のBox連携・完了報告・次アクション選択

このステップは以下の4つのサブステップで構成される。**Boxアップロードだけで完了としてはならない。** 12-1〜12-4 をすべて順番に完了させること。

| サブステップ | 内容 |
|------------|------|
| 12-1 | `claude_in_pptx_prompt.md` の存在確認（なければ生成・Boxアップロード） |
| 12-2 | story.md / assets/ を Box にアップロード |
| 12-3 | Box フォルダ URL を取得 |
| 12-4 | 完了報告（`### 次のステップ` セクション**省略禁止**） |

---

## 12-1: `claude_in_pptx_prompt.md` の生成・アップロード

**スキップ禁止。必ず実行すること。**

1. `.claude/skills/gaido-proposal-slide-generator/references/ClaudeInPowerPointPrompt.md` を Read する
2. `{...}` プレースホルダーを実際のスライド情報（使用した色・フォント・スライド構成等）で埋める
3. 埋めた内容を `ai_generated/proposals/{案件名}/claude_in_pptx_prompt.md` として保存する（既存ファイルは上書き）
4. `.box/credentials.json` が存在する場合、Box にアップロードする
   ```bash
   python3 tools/box_client.py upload \
     ai_generated/proposals/{案件名}/claude_in_pptx_prompt.md \
     --folder-path "GAiDo/{案件名}/proposal"
   ```

---

## 12-2: story.md / assets/ を Box にアップロード

```bash
python3 tools/box_client.py upload \
  ai_generated/proposals/{案件名}/story.md \
  --folder-path "GAiDo/{案件名}/proposal"
# assets/ 内のファイルを1件ずつアップロード
for f in ai_generated/proposals/{案件名}/assets/*; do
  [ -f "$f" ] && python3 tools/box_client.py upload "$f" \
    --folder-path "GAiDo/{案件名}/proposal/assets"
done
```

---

## 12-3: Box フォルダ URL を取得

```python
# BoxフォルダIDを取得してURLを構築する
import subprocess, json, sys
result = subprocess.run(
    ["python3", "tools/box_client.py", "list", "--folder-path", "GAiDo/{案件名}/proposal"],
    capture_output=True, text=True
)
# box_client.py list の出力からフォルダIDを取得できない場合は resolve_folder_path を使う
from tools.box_client import BoxClient
client = BoxClient()
folder_id = client.resolve_folder_path("GAiDo/{案件名}/proposal")
box_url = f"https://app.box.com/folder/{folder_id}"
print(box_url)
```

---

## 12-4: 完了報告 ＋ AskUserQuestion

**⚠️ 省略禁止**: キャラクター口調への書き換えは許可するが、`### 次のステップ` セクション（Claude in PowerPoint推奨・draw.io編集案内・URL含む）は**構造・内容を保持したまま出力すること**。

取得した `box_url` を使い、以下のフォーマットでユーザーに完了報告すること:

---

## 提案書が完成しました

### 成果物一覧（Box: 取得した folder_id を `https://app.box.com/folder/{folder_id}` 形式のリンクとして出力すること）

| ファイル | 内容 |
|---------|------|
| `proposal.pptx` | 提案書スライド（完成版） |
| `claude_in_pptx_prompt.md` | Claude in PowerPoint 仕上げ用プロンプト |
| `story.md` | スライド構成・ナレーション原稿 |
| `assets/` | draw.io 図ファイル（編集可能） |

### 次のステップ

#### 1. プロジェクト計画書・リスク計画書を作成する

この提案書を入力資料として、以下を自動生成できます。

| 作成物 | スキル |
|--------|--------|
| プロジェクト計画書（PPTX） | `/gaido-proposal-project-plan` |
| リスク計画書（Excel） | `/gaido-proposal-risk-plan` |
| 上記2つを作成する | `/gaido-proposal-project-plan` → 完了後に `/gaido-proposal-risk-plan` |

#### 2. Claude in PowerPoint で仕上げる

PPTXをダウンロードしてPowerPointで開き、Claude in PowerPoint アドインで仕上げを行うことをお勧めします。

**アドインのインストール手順（未インストールの場合）:**
1. [Microsoft Marketplace の Claude for PowerPoint ページ](https://marketplace.microsoft.com/en-us/product/office/WA200010001?tab=Overview) にアクセスして「Get it now」をクリック
2. 「Get it now」でインストール
3. PowerPoint を開いてアドインを有効化 → Claude アカウントでサインイン

参考: https://support.claude.com/en/articles/13521390-use-claude-for-powerpoint

**仕上げ用プロンプト:** Box の `claude_in_pptx_prompt.md` を開き、内容をClaude in PowerPointに貼り付けて実行してください。

#### 3. draw.io 図を編集する（必要に応じて）

Box の `assets/` フォルダに draw.io ファイルがあります。[draw.io](https://app.diagrams.net/) でファイルを開いて編集し、PowerPoint に貼り直すことができます。

---

> プロジェクト計画書やリスク計画書を続けて作成したい場合は、その旨をメッセージしてください。この提案書を入力資料として自動生成します。
