#!/usr/bin/env bash
set -euo pipefail

# use-exclusive-todo-file.sh — 排他制御付きtodoファイル管理
#
# 使い方:
#   use-exclusive-todo-file.sh init <todoファイル絶対パス>
#   use-exclusive-todo-file.sh is-completed <todoファイル絶対パス>
#   use-exclusive-todo-file.sh next <todoファイル絶対パス>
#   use-exclusive-todo-file.sh done <todoファイル絶対パス> <nextで取得した文字列>
#   use-exclusive-todo-file.sh fail <todoファイル絶対パス> <nextで取得した文字列>
#   use-exclusive-todo-file.sh release <todoファイル絶対パス> <nextで取得した文字列>
#   use-exclusive-todo-file.sh reset-doing <todoファイル絶対パス>
#
# 排他制御の仕組み:
#   flock コマンド（util-linux）でLinuxカーネルのファイルロック機能を利用する。
#   ロック状態はカーネルが管理し、ロックファイルの存在有無ではなく、
#   どのプロセスがロックを保持しているかで判定される。
#   プロセスが異常終了した場合もカーネルが自動的にロックを解放するため、
#   デッドロックは発生しない。
#
#   スクリプト内では以下のパターンで排他制御を行う:
#     (
#       flock -x "$fd"      # fd に対して排他ロックを取得
#                           # 他プロセスがロック中の場合はエラーにならず、解放されるまで待機する
#                           # （即エラーにしたい場合は -n オプションだが、ここでは順番待ちが適切）
#       # ロック取得済み。ここでtodoファイルを安全に読み書きする
#     ) {fd}>"$LOCK_FILE"   # シェル内の空きFD番号を自動取得し、ロックファイルを紐付ける
#                           # サブシェル終了時にfdが閉じられ、ロックが自動解放される
#
# 終了コード:
#   0: 成功
#   1: 対象タスクなし（next: 未着手なし、done/fail/release: 該当行なし、is-completed: 未完了あり）
#       または init でファイルが既に存在する
#   2: 引数エラー・ファイル不在

COMMAND="${1:-}"
TODO_FILE="${2:-}"

if [[ -z "$COMMAND" || -z "$TODO_FILE" ]]; then
  echo "Usage: $0 {init|is-completed|next|done|fail|release|reset-doing} <todoファイル絶対パス> [<nextで取得した文字列>]" >&2
  exit 2
fi

# init コマンドはファイルが存在しないことが前提なので、存在チェックを分岐
if [[ "$COMMAND" != "init" && ! -f "$TODO_FILE" ]]; then
  echo "Error: $TODO_FILE が見つかりません" >&2
  exit 2
fi

# ロックファイルはtodoファイルと同じディレクトリに生成される。
# flockのロック状態はカーネルが管理するため、ロックファイルは
# スクリプト終了後も残留するが、これは正常な動作であり削除不要。
LOCK_FILE="${TODO_FILE}.lock"

case "$COMMAND" in
  init)
    # 標準入力から1行1タスクを読み取り、各行に "- [ ] " プレフィックスを付けて
    # todoファイルを新規作成する。AIが直接ファイルを書くとフォーマットが崩れる
    # リスクがあるため、必ずこのコマンド経由で作成すること。
    if [[ -f "$TODO_FILE" ]]; then
      echo "Error: $TODO_FILE は既に存在します。上書きはできません" >&2
      exit 1
    fi

    (
      flock -x "$fd"

      while IFS= read -r line; do
        # 空行はスキップ
        if [[ -n "$line" ]]; then
          echo "- [ ] ${line}"
        fi
      done > "$TODO_FILE"
    ) {fd}>"$LOCK_FILE"
    ;;

  is-completed)
    # todoファイル内に未着手（- [ ] ）または処理中（- [>] ）の行が
    # 存在しないことを確認する。
    # 完了（- [x] ）と失敗（- [!] ）はどちらも完了扱い。
    is_completed_result=0
    (
      flock -x "$fd"

      REMAINING=$(grep -c -E '^- \[ \] |^- \[>\] ' "$TODO_FILE" || true)
      if [[ "$REMAINING" -gt 0 ]]; then
        exit 1
      fi
    ) {fd}>"$LOCK_FILE" || is_completed_result=$?
    exit "$is_completed_result"
    ;;

  next)
    # サブシェルの終了コードを明示的に伝播させる。
    # exit 1（未着手タスクなし）は正常なループ終了の合図であり、
    # set -e による強制終了ではなく呼び出し元に返す必要がある。
    next_result=0
    (
      flock -x "$fd"

      # 最初の未着手行（- [ ] ）を検索
      LINE=$(grep -n -m1 '^- \[ \] ' "$TODO_FILE" || true)
      if [[ -z "$LINE" ]]; then
        exit 1
      fi

      LINE_NUM="${LINE%%:*}"
      if [[ -z "$LINE_NUM" ]]; then
        echo "Error: 行番号の取得に失敗しました" >&2
        exit 1
      fi

      # テキスト部分を抽出（"- [ ] " の6文字を除去）
      TASK_TEXT="${LINE#*- \[ \] }"

      # - [ ] → - [>] に変更
      sed -i "${LINE_NUM}s/^- \[ \] /- [>] /" "$TODO_FILE"

      # テキストを標準出力に返す（改行なし）
      printf '%s' "$TASK_TEXT"
    ) {fd}>"$LOCK_FILE" || next_result=$?
    exit "$next_result"
    ;;

  done)
    DONE_TEXT="${3:-}"
    if [[ -z "$DONE_TEXT" ]]; then
      echo "Usage: $0 done <todoファイル絶対パス> <nextで取得した文字列>" >&2
      exit 2
    fi

    # サブシェルの終了コードを明示的に伝播させる
    done_result=0
    (
      flock -x "$fd"

      # 該当する処理中行（- [>] ）を完了（- [x] ）に変更
      # -x: 行全体一致（部分一致による誤マッチを防止）
      # -F: 固定文字列検索（正規表現メタ文字の影響を回避）
      LINE=$(grep -n -xF -- "- [>] ${DONE_TEXT}" "$TODO_FILE" | head -1 || true)
      if [[ -z "$LINE" ]]; then
        echo "Error: 処理中の該当行が見つかりません: ${DONE_TEXT}" >&2
        exit 1
      fi

      LINE_NUM="${LINE%%:*}"
      if [[ -z "$LINE_NUM" ]]; then
        echo "Error: 行番号の取得に失敗しました" >&2
        exit 1
      fi

      sed -i "${LINE_NUM}s/^- \[>\] /- [x] /" "$TODO_FILE"
    ) {fd}>"$LOCK_FILE" || done_result=$?
    exit "$done_result"
    ;;

  fail)
    # リトライ不可の失敗時に使用。
    # 処理中タスク（- [>] ）を失敗（- [!] ）に変更し、以後nextの取得対象から除外する。
    # is-completedでは完了扱い（未着手・処理中が残っていなければ完了）。
    FAIL_TEXT="${3:-}"
    if [[ -z "$FAIL_TEXT" ]]; then
      echo "Usage: $0 fail <todoファイル絶対パス> <nextで取得した文字列>" >&2
      exit 2
    fi

    fail_result=0
    (
      flock -x "$fd"

      LINE=$(grep -n -xF -- "- [>] ${FAIL_TEXT}" "$TODO_FILE" | head -1 || true)
      if [[ -z "$LINE" ]]; then
        echo "Error: 処理中の該当行が見つかりません: ${FAIL_TEXT}" >&2
        exit 1
      fi

      LINE_NUM="${LINE%%:*}"
      if [[ -z "$LINE_NUM" ]]; then
        echo "Error: 行番号の取得に失敗しました" >&2
        exit 1
      fi

      sed -i "${LINE_NUM}s/^- \[>\] /- [!] /" "$TODO_FILE"
    ) {fd}>"$LOCK_FILE" || fail_result=$?
    exit "$fail_result"
    ;;

  release)
    # リトライ可能な失敗時に使用（レートリミット、ネットワークエラー等）。
    # 処理中タスク（- [>] ）を未着手（- [ ] ）に戻し、
    # 他のワーカーまたは自分が再度nextで取得できるようにする。
    RELEASE_TEXT="${3:-}"
    if [[ -z "$RELEASE_TEXT" ]]; then
      echo "Usage: $0 release <todoファイル絶対パス> <nextで取得した文字列>" >&2
      exit 2
    fi

    release_result=0
    (
      flock -x "$fd"

      LINE=$(grep -n -xF -- "- [>] ${RELEASE_TEXT}" "$TODO_FILE" | head -1 || true)
      if [[ -z "$LINE" ]]; then
        echo "Error: 処理中の該当行が見つかりません: ${RELEASE_TEXT}" >&2
        exit 1
      fi

      LINE_NUM="${LINE%%:*}"
      if [[ -z "$LINE_NUM" ]]; then
        echo "Error: 行番号の取得に失敗しました" >&2
        exit 1
      fi

      sed -i "${LINE_NUM}s/^- \[>\] /- [ ] /" "$TODO_FILE"
    ) {fd}>"$LOCK_FILE" || release_result=$?
    exit "$release_result"
    ;;

  reset-doing)
    # システムダウンからの復旧用。
    # 完了できなかった処理中タスク（- [>] ）をすべて未着手（- [ ] ）に戻し、
    # 再度nextで取得可能な状態にする。
    # **Workerが全停止している状態で実行すること。
    # 並列実行中に実行するとタスクが重複実行される。**
    reset_result=0
    (
      flock -x "$fd"

      DOING_COUNT=$(grep -c '^- \[>\] ' "$TODO_FILE" || true)
      sed -i 's/^- \[>\] /- [ ] /g' "$TODO_FILE"
      echo "${DOING_COUNT} 件のタスクを未着手に戻しました" >&2
    ) {fd}>"$LOCK_FILE" || reset_result=$?
    exit "$reset_result"
    ;;

  *)
    echo "Error: 不明なコマンド: $COMMAND" >&2
    echo "Usage: $0 {init|is-completed|next|done|fail|release|reset-doing} <todoファイル絶対パス> [<nextで取得した文字列>]" >&2
    exit 2
    ;;
esac
