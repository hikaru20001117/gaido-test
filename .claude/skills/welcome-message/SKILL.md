---
name: welcome-message
description: 「新しくチャットを始めます。何ができるか教えて（このメッセージは自動で送信されています）」を受け取ったときに実行。メェナビ自己紹介と利用可能機能紹介、次のアクションをASKで選択させる（メインエージェント専用）
---

# ウェルカムメッセージ

ユーザーから「新しくチャットを始めます。何ができるか教えて（このメッセージは自動で送信されています）」を受け取ったときに、メェナビが自己紹介し、利用可能な機能を紹介し、次のアクションをユーザーに選択させる。

## フロー

```mermaid
flowchart TD
    A["スキル開始"] --> B["使用モデル情報と起動モードを取得"]
    B --> C{"LAUNCH_MODE"}
    C -->|"dev"| D1["機能紹介（全機能）を表示"]
    C -->|"quick"| D2["機能紹介（GitHub不要機能のみ）を表示"]
    D1 --> E["AskUserQuestion<br>1段階目: カテゴリ選択（全カテゴリ）"]
    D2 --> BOX["AskUserQuestion<br>Boxのアップロード先フォルダを指定してください"]
    BOX --> E2["AskUserQuestion<br>1段階目: カテゴリ選択（開発除く）"]
    E --> F{"カテゴリ"}
    E2 --> F2{"カテゴリ"}
    F -->|"システム開発・改修"| G["AskUserQuestion<br>2段階目: 開発メニュー"]
    F -->|"営業支援"| H["AskUserQuestion<br>2段階目: 営業支援メニュー"]
    F -->|"資料作成"| HA["AskUserQuestion<br>2段階目: 資料作成メニュー"]
    F -->|"その他のサポート"| I["AskUserQuestion<br>2段階目: サポートメニュー"]
    F2 -->|"営業支援"| H
    F2 -->|"資料作成"| HA
    F2 -->|"その他のサポート"| I
    G -->|"新しいシステムを開発する"| J["welcome-message手順完了<br>phase-workflowに従い進行"]
    G -->|"既存のシステムを改修する"| K["welcome-message手順完了<br>phase-workflowに従い進行"]
    H -->|"営業案件を相談する"| L["welcome-message手順完了<br>orchestration-guideが /project-advisor を実行"]
    H -->|"案件の振り返りを記録する"| N["Skillツールで /gaido-deal-feedback を実行"]
    H -->|"人格シミュレーションを作成する"| R1["Skillツールで /gaido-persona-generator を実行"]
    HA -->|"提案書を作成する"| M["welcome-message手順完了<br>orchestration-guideが /gaido-proposal-init を実行"]
    HA -->|"見積・PLシートを作成する"| R2["Skillツールで /gaido-estimate-pl-generator を実行"]
    HA -->|"プロジェクト計画書/リスク計画書を作成する"| S["AskUserQuestionでどちらを作成するか確認し<br>Skillツールで /gaido-proposal-project-plan か /gaido-proposal-risk-plan を実行"]
    I -->|"法務関連サポート"| O["Skillツールで法務スキルを実行"]
    I -->|"バグを報告する"| P["Skillツールで /gaido-report-ticket:gaido-report-ticket-of-bug-from-user を実行"]
    I -->|"機能要望を伝える"| Q["Skillツールで /gaido-report-ticket:gaido-report-ticket-of-feature-request-from-user を実行"]
```

## Step 1: 使用モデル情報と起動モードの取得・github-mode.md の再生成

Bashで以下のコマンドをまとめて実行する。
起動モードは entrypoint.sh が設定した `$LAUNCH_MODE` env var で判定する（`dev` = アプリ開発モード、`quick` = 資料作成モード）。

```bash
claude --version

echo "LAUNCH_MODE=$LAUNCH_MODE"

if [ "$LAUNCH_MODE" = "dev" ]; then
    cat > /workspace/target_repo/.claude/rules/github-mode.md << 'EOF'
# GitHub連携状態: 設定済み

アプリケーション開発（backlog/develop/test/finalizeフェーズ）が利用可能。
gh コマンドを通常通り使用してよい。
EOF
else
    cat > /workspace/target_repo/.claude/rules/github-mode.md << 'EOF'
# GitHub連携状態: 未設定

**重要制限:**
- アプリ開発（バックログ作成・実装・テスト・PR作成・Issue管理）は利用不可
- ユーザーからアプリ開発を依頼された場合は「GitHub連携が設定されていないため、アプリ開発はできません。GAiDoアプリのStep 2でGitHub設定を行ってください。」と案内すること
- `gh` コマンド（gh repo view / gh issue / gh pr 等）は実行しないこと
- `git commit` および `git push` は実行しないこと（成果物の保存はBoxのみ。tools/box_client.py を使用）
EOF
fi
```

- モデル情報が取得できない場合は「モデル情報は確認できませんでした」として先に進む
- `$LAUNCH_MODE=dev` の場合はアプリ開発モード、`quick` または未設定の場合は資料作成モードとして以降のステップを分岐させる

## Step 2: メェナビ自己紹介と機能紹介の表示

`/gaido-menavi-character` の口調ルールに従い、メェナビとして以下の内容を表示する。

### 自己紹介

- 自己紹介文（メェナビの口調で）
- 使用モデル: Step 1で取得した情報

### 利用可能な機能の紹介

**$LAUNCH_MODE=dev（アプリ開発モード）の場合:**

以下の機能をリスト形式で簡潔に紹介する:

- **新規システム開発**: 対話で要件を練り上げ、設計・実装・テストまで全自動で開発
- **既存システム改修**: 既存のソースコードを解析し、改修を実施
- **営業案件アドバイザー**: 案件のヒアリング・スコアリング・Go/No Go判定
- **案件の振り返り**: 提案後の受注/失注/辞退結果を記録し、振り返りレポートを作成
- **人格シミュレーション生成**: エゴグラムと壁打ちで壁打ち相手・顧客のペルソナを生成
- **提案書作成**: RFP等をもとにスライド構成を壁打ちし、PowerPointを生成
- **見積・PLシート作成**: 複数社の原価見積を統合し、PL表・顧客提示用の見積Excelを生成
- **プロジェクト計画書/リスク計画書作成**: 提案書をもとにプロジェクト計画書・リスク計画書を生成
- **法務関連サポート** — 契約書レビュー、OSSライセンスチェック、利用規約・プライバシーポリシー生成
- **バグ報告**: GAiDoアプリのバグをIssue登録
- **機能要望**: GAiDoアプリへの要望をIssue登録

**$LAUNCH_MODE=quick（資料作成モード）の場合:**

以下の機能をリスト形式で簡潔に紹介する。GitHub未設定のため、システム開発・改修は利用できない旨を添える:

- **営業案件アドバイザー**: 案件のヒアリング・スコアリング・Go/No Go判定
- **案件の振り返り**: 提案後の受注/失注/辞退結果を記録し、振り返りレポートを作成
- **人格シミュレーション生成**: エゴグラムと壁打ちで壁打ち相手・顧客のペルソナを生成
- **提案書作成**: RFP等をもとにスライド構成を壁打ちし、PowerPointを生成
- **見積・PLシート作成**: 複数社の原価見積を統合し、PL表・顧客提示用の見積Excelを生成
- **プロジェクト計画書/リスク計画書作成**: 提案書をもとにプロジェクト計画書・リスク計画書を生成
- **法務関連サポート** — 契約書レビュー、OSSライセンスチェック、利用規約・プライバシーポリシー生成
- **バグ報告**: GAiDoアプリのバグをIssue登録
- **機能要望**: GAiDoアプリへの要望をIssue登録

※ システム開発・改修を使うには、GAiDoアプリのStep 2でGitHub連携を設定してから再起動が必要である旨を案内すること

## Step 2.5: Boxアップロード先フォルダの確認（quickモードのみ）

`$LAUNCH_MODE` が `quick`（または未設定）の場合のみ実行する。

AskUserQuestionで以下を確認する:

- **question**: 「Boxのアップロード先フォルダを指定してください」
- **header**: 「Boxフォルダ」
- **options**:
  - label: `OtherにBoxフォルダのURLまたはIDを入力してください`
    description: `URLまたはIDをOtherのテキスト入力欄に入力してください`
  - label: `入力例を確認する`
    description: `URL例: https://xxx.ent.box.com/folder/123456 / ID例: 123456`

ユーザーが入力した値（Otherのテキスト）から以下のPythonスクリプトで
`/workspace/target_repo/.box/credentials.json` の `base_folder_id` を更新する:

```bash
python3 - << 'PYEOF'
import json, re

folder_input = "<ユーザーが入力した値>"
match = re.search(r'/folder/(\d+)', folder_input)
folder_id = match.group(1) if match else folder_input.strip()

creds_path = '/workspace/target_repo/.box/credentials.json'
with open(creds_path) as f:
    creds = json.load(f)
creds['base_folder_id'] = folder_id
with open(creds_path, 'w') as f:
    json.dump(creds, f)
print(f"base_folder_id を {folder_id} に設定しました")
PYEOF
```

設定完了後、Step 3（AskUserQuestion）へ進む。

## Step 3: AskUserQuestion（1段階目: カテゴリ選択）

ASKツールには最大4択+otherという制約があるため、2段階選択方式を採用する。
1段階目でカテゴリを選び、2段階目で具体的な機能を選択する。

**質問**: 「何をするなのです？」

**$LAUNCH_MODE=dev（アプリ開発モード）の選択肢**:

| label | description |
|-------|-------------|
| システム開発・改修 | 新規開発や既存システムの改修を行うなのです |
| 営業支援 | 案件相談・案件の振り返り・人格シミュレーションなのです |
| 資料作成 | 提案書・見積・PLシート・プロジェクト計画書/リスク計画書の生成なのです |
| その他のサポート | 法務関連・バグ報告・機能要望なのです |

**$LAUNCH_MODE=quick（資料作成モード）の選択肢**:

| label | description |
|-------|-------------|
| 営業支援 | 案件相談・案件の振り返り・人格シミュレーションなのです |
| 資料作成 | 提案書・見積・PLシート・プロジェクト計画書/リスク計画書の生成なのです |
| その他のサポート | 法務関連・バグ報告・機能要望なのです |

## Step 4: AskUserQuestion（2段階目: 機能選択）

1段階目の選択に応じて、2段階目の選択肢を提示する。

### 「システム開発・改修」を選んだ場合（$LAUNCH_MODE=dev のときのみ表示）

**質問**: 「どちらなのです？」

| label | description |
|-------|-------------|
| 新しいシステムを開発する | 対話で要件を練り上げ、設計・実装・テストまで全自動で開発するなのです |
| 既存のシステムを改修する | 既存のソースコードを解析し、改修を実施するなのです |

### 「営業支援」を選んだ場合

**質問**: 「営業支援メニューなのです！何をするなのです？」

| label | description |
|-------|-------------|
| 営業案件を相談する | 案件のヒアリング・スコアリング・判定を行うなのです |
| 案件の振り返りを記録する | 提案後の受注/失注/辞退結果を記録し、振り返りレポートを作成するなのです |
| 人格シミュレーションを作成する | エゴグラムベースで壁打ち相手のペルソナを生成するなのです |

### 「資料作成」を選んだ場合

**質問**: 「資料作成メニューなのです！何を作るなのです？」

| label | description |
|-------|-------------|
| 提案書を作成する | RFP等をもとにスライド構成を壁打ちし、PowerPointを生成するなのです |
| 見積・PLシートを作成する | 複数社の原価見積を統合し、PL表・見積Excelを生成するなのです |
| プロジェクト計画書/リスク計画書を作成する | 提案書をもとにプロジェクト計画書（PPTX）・リスク計画書（Excel）を生成するなのです |

### 「その他のサポート」を選んだ場合

**質問**: 「サポートメニューなのです！何をするなのです？」

| label | description |
|-------|-------------|
| 法務関連サポート | 契約書レビュー・OSSライセンスチェック・利用規約生成なのです |
| バグを報告する | GAiDoアプリのバグをIssue登録するなのです |
| 機能要望を伝える | GAiDoアプリへの要望をIssue登録するなのです |

## Step 5: 選択結果に応じた遷移

ユーザーの選択に応じて、以下のように遷移する。

| 選択 | 遷移先 |
|------|--------|
| 新しいシステムを開発する | welcome-message手順完了。以後はphase-workflowの定義に従い進行する |
| 既存のシステムを改修する | welcome-message手順完了。以後はphase-workflowの定義に従い進行する |
| 営業案件を相談する | welcome-message手順完了。以後はorchestration-guideが `/project-advisor` を実行 |
| 提案書を作成する | welcome-message手順完了。以後はorchestration-guideが `/gaido-proposal-init` を実行 |
| 見積・PLシートを作成する | Skillツールで `/gaido-estimate-pl-generator` を実行 |
| 案件の振り返りを記録する | Skillツールで `/gaido-deal-feedback` を実行 |
| 人格シミュレーションを作成する | Skillツールで `/gaido-persona-generator` を実行 |
| プロジェクト計画書/リスク計画書を作成する | AskUserQuestionで「プロジェクト計画書を作成する」「リスク計画書を作成する」「上記2つを作成する」のいずれかを確認し、選択に応じてSkillツールで `/gaido-proposal-project-plan`、`/gaido-proposal-risk-plan`、または両方を順に実行 |
| 法務関連サポート | Skillツールで 契約書レビュー (/gaido-legal-review)、OSSライセンスチェック (/gaido-legal-oss-check)、利用規約・プライバシーポリシー生成 (/gaido-legal-policy) のいずれかをユーザーに確認して実行 |
| バグを報告する | Skillツールで `/gaido-report-ticket:gaido-report-ticket-of-bug-from-user` を実行 |
| 機能要望を伝える | Skillツールで `/gaido-report-ticket:gaido-report-ticket-of-feature-request-from-user` を実行 |
| Other（自由入力） | スキル呼び出しは行わず、ユーザーの入力内容に応じて対話を続行 |

## 注意事項

- このスキルはメインエージェント専用。SubAgentから実行してはならない
- `/gaido-menavi-character` の口調ルールが適用された状態で実行されることを前提とする
- AskUserQuestionの `questions` パラメータは必ず配列型で渡すこと（JSON文字列は不可）
