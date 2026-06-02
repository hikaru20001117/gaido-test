#!/usr/bin/env bash
set -euo pipefail

# comment-orchestrator.sh — comment-writer.shをN並列で起動し、残留チェック・再投入を制御するスクリプト
#
# 使い方:
#   comment-orchestrator.sh <N> <TODO_FILE> <RULES_FILE> <MAX_ROUNDS>
#
# 引数:
#   N           : comment-writer.shの最大並列起動数
#   TODO_FILE   : todoファイルの絶対パス
#   RULES_FILE  : claude -pに渡すsystem-prompt-fileのパス
#   MAX_ROUNDS  : 最大再投入ラウンド数
#
# 前提条件:
#   - gitリポジトリルートをカレントディレクトリとして実行すること
#   - CLAUDE_CODE_TOKEN環境変数が設定されていること
#
# 終了コード:
#   0: 全タスク完了（[!]を含む完了扱い）
#   1: MAX_ROUNDSラウンド経過しても未完了タスクが残っている
#   2: 設定エラー（CONFIG_ERROR）が発生
#
# 結果ファイル:
#   progress/orchestrator_result.txt にRESULTとROUNDを出力
#
# ワーカー起動戦略（adaptive ramp-up）:
#   1. INITIAL_BATCH人を同時起動
#   2. PROBE_INTERVAL_SEC秒待機
#   3. 稼働中ワーカーのログにRATE_LIMITが出ていないか確認
#   4. 出ていなければ1人追加 → 2に戻る
#   5. 出ていたら追加打ち止め、既存ワーカーの完了を待つ

# === 引数 ===
N="${1:?Usage: comment-orchestrator.sh <N> <TODO_FILE> <RULES_FILE> <MAX_ROUNDS>}"
TODO="${2:?}"
RULES_FILE="${3:?}"
MAX_ROUNDS="${4:?}"

# === 定数 ===
SCRIPT=".claude/skills/use-exclusive-todo-file/scripts/use-exclusive-todo-file.sh"
WRITER=".claude/skills/existing-source-analysis-operations/scripts/comment-writer.sh"
PROGRESS_DIR="ai_generated/intermediate_files/from_source/progress"
RESULT_FILE="${PROGRESS_DIR}/orchestrator_result.txt"
# ラウンド間backoff（秒）
BACKOFF_RATE_LIMIT_SEC=120
BACKOFF_OTHER_SEC=30
# adaptive ramp-up
INITIAL_BATCH=2         # 最初に同時起動するワーカー数
PROBE_INTERVAL_SEC=120  # 追加ワーカー投入前の観測時間（秒）

# === メインループ ===
for (( round=0; round<MAX_ROUNDS; round++ )); do
  PIDS=()
  SUMMARY_FILES=()
  WORKER_LOGS=()

  # 1. ワーカー起動（adaptive ramp-up）
  LAUNCHED=0
  RATE_LIMIT_DETECTED=false

  for (( i=0; i<N; i++ )); do
    # --- INITIAL_BATCH以降: probe して判断 ---
    if [ "$i" -ge "$INITIAL_BATCH" ]; then
      sleep "$PROBE_INTERVAL_SEC"

      # 稼働中ワーカーのログにRATE_LIMIT/INVALID_API_KEYイベントが出ていないか確認
      # 注: "RATE_LIMIT" だけだとCONFIG行の MAX_CONSECUTIVE_RATE_LIMIT=5 にもマッチするため、
      #      "] RATE_LIMIT" でログメッセージの先頭部分のみを対象とする。
      #      RATE_LIMIT_STOP（新タグ、プランL7.24）もこのパターンでマッチする（prefix match）。
      #      INVALID_API_KEY（新タグ、プランL7.24）もramp-upを止める契機とする
      #      （トークンブロック中は新規起動しても連鎖失敗するため）
      if grep -qlE "] RATE_LIMIT|] INVALID_API_KEY" "${WORKER_LOGS[@]}" 2>/dev/null; then
        RATE_LIMIT_DETECTED=true
        echo "RAMP_UP: rate limit or invalid api key detected after ${LAUNCHED} workers, stopping ramp-up" >&2
        break
      fi
    fi

    # --- ワーカー起動 ---
    WORKER_ID=$((round * 100 + i))
    SUMMARY_FILE="${PROGRESS_DIR}/comment_writer_${WORKER_ID}_summary.out"
    WORKER_LOG="${PROGRESS_DIR}/comment_writer_${WORKER_ID}.log"
    SUMMARY_FILES+=("$SUMMARY_FILE")
    WORKER_LOGS+=("$WORKER_LOG")

    # 前回ランの古いログをtruncate（probe時の偽陽性防止）
    > "$WORKER_LOG"

    bash "$WRITER" "$WORKER_ID" "$TODO" "$RULES_FILE" \
      > "$SUMMARY_FILE" \
      2>>"${PROGRESS_DIR}/comment_writer_${WORKER_ID}_stderr.log" &
    PIDS+=($!)
    LAUNCHED=$((LAUNCHED + 1))
  done

  echo "RAMP_UP: round=$round launched=$LAUNCHED/$N rate_limit_detected=$RATE_LIMIT_DETECTED" >&2

  # 2. 全プロセス完了を待機（PID別に終了コードを取得）
  WORKER_EXIT_CODES=()
  for (( i=0; i<${#PIDS[@]}; i++ )); do
    wait "${PIDS[$i]}" && WORKER_EXIT_CODES+=("0") || WORKER_EXIT_CODES+=("$?")
  done

  # 3. サマリ収集・異常検出
  ANY_CONFIG_ERROR=false
  ANY_RATE_LIMIT_EXIT=false

  for (( i=0; i<${#SUMMARY_FILES[@]}; i++ )); do
    SF="${SUMMARY_FILES[$i]}"

    # ワーカー異常終了検出（サマリファイルが空 = 標準出力を出す前にクラッシュ）
    if [ ! -s "$SF" ]; then
      echo "WARNING: Worker $((round * 100 + i)) crashed (exit=${WORKER_EXIT_CODES[$i]}, no summary)" >&2
      continue
    fi

    if grep -q "CONFIG_ERROR=true" "$SF"; then
      ANY_CONFIG_ERROR=true
    fi
    if grep -q "RATE_LIMIT_EXIT=true" "$SF"; then
      ANY_RATE_LIMIT_EXIT=true
    fi
  done

  # 4. CONFIG_ERROR → 即時終了
  if [ "$ANY_CONFIG_ERROR" = true ]; then
    echo "RESULT=CONFIG_ERROR" > "$RESULT_FILE"
    echo "ROUND=$round" >> "$RESULT_FILE"
    exit 2
  fi

  # 5. 残留チェック
  DOING=$(grep -c '^\- \[>\]' "$TODO" 2>/dev/null || true)
  DOING=${DOING:-0}
  PENDING=$(grep -c '^\- \[ \]' "$TODO" 2>/dev/null || true)
  PENDING=${PENDING:-0}

  # [>] 残留 = ワーカークラッシュ → reset-doing
  if [ "$DOING" -gt 0 ]; then
    "$SCRIPT" reset-doing "$TODO"
    PENDING=$((PENDING + DOING))
  fi

  # 全完了
  if [ "$PENDING" -eq 0 ]; then
    echo "RESULT=COMPLETE" > "$RESULT_FILE"
    echo "ROUND=$round" >> "$RESULT_FILE"
    exit 0
  fi

  # 6. 次ラウンドの準備
  # rate limit検出時: 5hスライディングウィンドウは短時間では回復しないため即時終了
  if [ "$ANY_RATE_LIMIT_EXIT" = true ] || [ "$RATE_LIMIT_DETECTED" = true ]; then
    echo "RATE_LIMIT detected: exiting immediately (5h window does not recover in minutes)" >&2
    echo "RESULT=RATE_LIMIT_STOP" > "$RESULT_FILE"
    echo "ROUND=$round" >> "$RESULT_FILE"
    exit 0
  fi
  # rate limit以外の理由での未完了: 短時間待機して再投入
  sleep "$BACKOFF_OTHER_SEC"

  # N を残留数に合わせる（残留数がNより少なければ縮小）
  if [ "$PENDING" -lt "$N" ]; then
    N="$PENDING"
  fi
done

# MAX_ROUNDS到達
echo "RESULT=MAX_ROUNDS_EXCEEDED" > "$RESULT_FILE"
echo "ROUND=$MAX_ROUNDS" >> "$RESULT_FILE"
exit 1
