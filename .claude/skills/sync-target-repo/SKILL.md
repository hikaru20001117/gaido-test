---
name: sync-target-repo
description: target_repo の clone/pull、git user 設定、.gitignore 整備、gaido 管理ファイルの commit/push を一括で行う初期化スキル。アプリ開発モードのメインエージェントが最初に実行する（メインエージェント専用）
---

# Target Repository Sync

`/workspace/target_repo` を `TARGET_REPO_URL` に同期する skill。`scripts/sync-target-repo.sh` を呼び出すだけ。`git commit` / `git push` を skill 経由（pockode 起動後）で実行することで、コンテナ起動時の git 失敗で pockode が止まる #745 を回避する。

## 実行タイミングと呼出経路

- **アプリ開発モード（`LAUNCH_MODE=dev`）**: メインエージェントがユーザーからの最初のメッセージ対応前に必ず実行
- **呼出経路**: `/workspace/target_repo/.claude/rules/github-mode.md` のアプリ開発モード版に「最初に `/sync-target-repo` を実行」指示があり、AI はそれに従う
- **SubAgent からの呼出禁止**: メインエージェント専用
- **資料作成モード（`LAUNCH_MODE=quick`）**: github-mode.md に呼出指示が無いため呼ばれない
- **複数回呼出**: 各処理が冪等（pull / `cp -a --update=none` / `.gitignore` idempotent 追記 / 差分なし時 no-op commit）なので害は無いが、通常は 1 回で十分

## 手順

```bash
bash /workspace/target_repo/.claude/skills/sync-target-repo/scripts/sync-target-repo.sh
```

スクリプト内部処理（詳細は `scripts/sync-target-repo.sh` のヘッダコメント参照）:
1. clone or pull（初回は一時 dir 経由 + `cp -a --update=none` で既存 gaido 管理ファイル保護）
2. git user (local config) 設定
3. `.gitignore` 必須 6 項目を idempotent 追記
4. gaido 管理ファイルの commit/push（差分なしなら no-op）

- **成功時**: 後続の起動時必須 skill (`/orchestration-guide`、`/phase-workflow`、`/gaido-menavi-character`) に進む
- **失敗時（非ゼロ exit）**: 下記「失敗時の対応」へ

## 失敗時の対応（stderr 解釈）

Bash tool の stderr に含まれる文言を以下で分類し、ユーザーに対応提案する。

| stderr に含まれる文言 | 原因カテゴリ | ユーザーへの対応提案 |
|---|---|---|
| `TARGET_REPO_URL is not set` | 環境変数未設定 | 本 skill はアプリ開発モードで呼ばれる前提。GAiDo アプリの Step 2 で GitHub 設定が完了しているか確認するよう案内 |
| `Repository mismatch` | bind mount に別リポジトリの残骸 | stderr に表示される `sudo rm -rf ...` コマンドでディレクトリを削除し、コンテナ再起動するよう案内 |
| `Authentication failed` / `Permission denied` / `could not read Username` / `remote: Permission` | GitHub 認証エラー | GAiDo アプリの Step 2 で GitHub PAT を更新するよう案内（有効期限・リポジトリアクセス権限・組織承認の確認） |
| `Could not resolve host` / `Connection refused` / `network is unreachable` / `Temporary failure` | ネットワーク | ネットワーク接続を確認するよう案内。企業プロキシ配下ならプロキシ設定の確認も促す |
| `divergent branches` / `Need to specify how to reconcile` / `CONFLICT` / `Merge conflict` | 分岐 / コンフリクト | `git log --oneline -10` と `git log --oneline origin/<branch> -10` で差分確認後、merge / rebase / reset のどれで解決するかユーザーと相談 |
| `Updates were rejected` / `failed to push some refs` / `non-fast-forward` | push 拒否 | pull と push の間にリモートが更新された可能性。`git pull --rebase` での取り込みを提案（実行はユーザー承認後） |
| 上記以外 | 不明 | stderr の内容をそのままユーザーに提示し、対応方針を相談 |

### 対応時の原則

- **対応提案の実施は必ずユーザー承認後**: `git pull --rebase` や手動 merge / rebase 等を勝手に実行しない
- **破壊的操作の禁止**: `git push --force` / `git reset --hard` 等はユーザーの明示的な指示がない限り実行しない
