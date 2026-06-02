#!/bin/bash
#
# target_repo を TARGET_REPO_URL に同期するスクリプト。/sync-target-repo skill から呼ばれる。
#
# 役割（4 ステップ）:
#   1. clone or pull: target_repo に .git があれば pull、無ければ一時 dir 経由で clone
#      してから cp -a --update=none で展開（entrypoint 配置の gaido 管理ファイルを保護）
#   2. git user 設定: target_repo の .git/config (local) に user.name / user.email を設定
#      (AI セッション中の git commit / git push の著者情報として使われる)
#   3. .gitignore 整備: gaido 必須の除外行を idempotent に追記（既存内容は完全保持）
#   4. gaido 管理ファイルの commit/push: .gitignore で除外されない更新分をリモートへ反映
#
# 前提:
#   - TARGET_REPO_URL が export 済み（アプリ開発モード）
#   - gh auth setup-git 済み（entrypoint Phase 2 で実施）
#   - target_repo に entrypoint Phase 4 配置済みの gaido 管理ファイルが存在
#
# 関連:
#   - Issue #758: コンテナ起動時の git 失敗で pockode 起動がブロックされる問題（#745）の根治
#   - plan: docs/concept/work_logs/2026-05-11_758_extract_git_to_skill.md

set -e

# -----------------------------------------------------------------------------
# ユーティリティ
# -----------------------------------------------------------------------------

# git URL を比較可能な正規形に変換する。
# 同一リポジトリの SSH 形式 (git@github.com:foo/bar.git) と HTTPS 形式
# (https://github.com/foo/bar) を同じ文字列にして比較できるようにする。
# Step 1 の「別リポジトリ切替」検出で使用。
normalize_git_url() {
    local url="$1"
    url="${url/#git@github.com:/https://github.com/}"
    url="${url/#git@/https://}"
    url="${url%.git}"
    url="${url%/}"
    echo "${url,,}"
}

# -----------------------------------------------------------------------------
# 前提チェック
# -----------------------------------------------------------------------------

TARGET_DIR="${TARGET_DIR:-/workspace/target_repo}"

if [ -z "$TARGET_REPO_URL" ]; then
    echo "ERROR: TARGET_REPO_URL is not set" >&2
    echo "" >&2
    echo "本スクリプトはアプリ開発モード (LAUNCH_MODE=dev) で呼ばれる前提です。" >&2
    echo "資料作成モード時は github-mode.md に呼出指示が無いため AI から呼ばれません。" >&2
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: Target directory does not exist: $TARGET_DIR" >&2
    exit 1
fi

cd "$TARGET_DIR"

# -----------------------------------------------------------------------------
# Step 1: clone or pull
# -----------------------------------------------------------------------------

if [ -d .git ]; then
    # 既存 clone 済みのケース。pull の前に「別リポジトリの残骸が居ないか」を検証する。
    # bind mount で前回起動時の別リポジトリが残っている状態で pull すると、
    # 別リポジトリの履歴に対して fetch しようとしてコンフリクトや権限エラーが
    # 発生するため、origin URL を normalize_git_url で正規化して一致確認する。
    CURRENT_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
    EXPECTED_NORM=$(normalize_git_url "$TARGET_REPO_URL")
    CURRENT_NORM=$(normalize_git_url "$CURRENT_ORIGIN")
    if [ -n "$CURRENT_ORIGIN" ] && [ "$EXPECTED_NORM" != "$CURRENT_NORM" ]; then
        echo "ERROR: Repository mismatch" >&2
        echo "  expected: $TARGET_REPO_URL" >&2
        echo "  current : $CURRENT_ORIGIN" >&2
        echo "" >&2
        echo "前回のセッションで別リポジトリのデータが残っています。" >&2
        echo "target_repo を削除してから再起動してください:" >&2
        echo "  [desktopプロファイル] sudo rm -rf ~/.gaido/<repoId>/target-repo" >&2
        echo "  [devプロファイル]     sudo rm -rf container_backup/" >&2
        exit 1
    fi

    echo "Pulling latest changes from $TARGET_REPO_URL..."
    git pull
else
    # 初回 clone のケース。target_repo は空ではない（entrypoint Phase 4 で gaido 管理
    # ファイルが配置済み）ため、`gh repo clone $TARGET_REPO_URL .` を直接実行すると
    # "destination path is not empty" で失敗する。一時 dir に clone してから
    # `cp -a --update=none` で target_repo にマージすることで、既存ファイル
    # （entrypoint 配置の最新版 gaido 管理ファイル）を上書きせず保護する。
    # リモートに過去 gaido push 由来の古い gaido 管理ファイルが残っていても
    # --update=none により skip される。
    TEMP_CLONE_DIR=$(mktemp -d -t target_repo_clone.XXXXXX)
    trap 'rm -rf "$TEMP_CLONE_DIR"' EXIT

    echo "Cloning $TARGET_REPO_URL into $TEMP_CLONE_DIR..."
    gh repo clone "$TARGET_REPO_URL" "$TEMP_CLONE_DIR"

    echo "Merging into $TARGET_DIR (preserving existing gaido-managed files)..."
    cp -a --update=none "$TEMP_CLONE_DIR/." "$TARGET_DIR/"
fi

# -----------------------------------------------------------------------------
# Step 2: git user 設定（local config）
# -----------------------------------------------------------------------------

# global config は触らず target_repo の .git/config に local config として書き込む
# （影響範囲を target_repo に限定）。AI セッション中の commit / push で著者情報として使われる。
GH_USER_NAME=$(gh api user --jq '.name // .login')
GH_USER_ID=$(gh api user --jq '.id')
GH_USER_LOGIN=$(gh api user --jq '.login')
git config user.name "$GH_USER_NAME"
git config user.email "${GH_USER_ID}+${GH_USER_LOGIN}@users.noreply.github.com"
echo "Configured git user: $GH_USER_NAME <${GH_USER_ID}+${GH_USER_LOGIN}@users.noreply.github.com>"

# -----------------------------------------------------------------------------
# Step 3: .gitignore 整備（idempotent 追記）
# -----------------------------------------------------------------------------

# gaido 必須の除外行を1行ずつ idempotent に追記する。既存 .gitignore の内容は完全保持、
# 重複行は追加しない（grep -qxF で完全一致確認）。
#   - .box/                : Box の credentials.json（refresh_token 含む機密）
#   - ssl-certificates/    : 企業プロキシ用証明書（gaido が毎回上書きで配置）
#   - tools/, pencil_template/, docs_with_ai/ : gaido 管理ファイル群（誤 commit 防止）
#   - ai_generated/input/  : Box からダウンロードした入力資料（機密性高）
TARGET_GITIGNORE="$TARGET_DIR/.gitignore"
touch "$TARGET_GITIGNORE"
for entry in ".box/" "ssl-certificates/" "tools/" "pencil_template/" "docs_with_ai/" "ai_generated/input/"; do
    if ! grep -qxF "$entry" "$TARGET_GITIGNORE"; then
        echo "$entry" >> "$TARGET_GITIGNORE"
    fi
done
echo "Updated .gitignore (idempotent append for gaido entries)"

# -----------------------------------------------------------------------------
# Step 4: gaido 管理ファイルの commit/push
# -----------------------------------------------------------------------------

# .gitignore で除外されない gaido 管理ファイルに変更があれば commit / push する。
# 差分が無ければ no-op（2 回目以降の呼出も冪等）。失敗時は git 自身の stderr が
# 呼び出し元 skill に届き、SKILL.md の「失敗時の対応」テーブルに従って AI が対応提案する。
git add -A
if ! git diff --cached --quiet; then
    echo "Committing gaido managed files..."
    git commit -m "chore: update gaido managed files"
    git push
else
    echo "No changes to commit."
fi

echo "Target repository sync completed."
