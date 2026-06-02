#!/usr/bin/env bash
set -euo pipefail

# comment-writer.sh — todoファイルから1件ずつタスクを取得し、claude -pでコメントを付与するスクリプト
#
# 使い方:
#   comment-writer.sh <WORKER_ID> <TODO_FILE> <RULES_FILE>
#
# 引数:
#   WORKER_ID   : ワーカー識別子（ログファイル名やサマリに使用）
#   TODO_FILE   : todoファイルの絶対パス
#   RULES_FILE  : claude -pに渡すsystem-prompt-fileのパス
#
# 前提条件:
#   - gitリポジトリルートをカレントディレクトリとして実行すること
#   - CLAUDE_CODE_TOKEN環境変数が設定されていること（--bare使用時のapiKeyHelper認証に必要）
#
# 終了コード:
#   0: 正常終了（全タスク処理完了またはタスクなし）
#   非ゼロ: スクリプトエラー

# === 引数 ===
WORKER_ID="${1:?Usage: comment-writer.sh <WORKER_ID> <TODO_FILE> <RULES_FILE>}"
TODO="${2:?}"
RULES_FILE="${3:?}"

# === 定数 ===
SCRIPT=".claude/skills/use-exclusive-todo-file/scripts/use-exclusive-todo-file.sh"
LOG="ai_generated/intermediate_files/from_source/progress/comment_writer_${WORKER_ID}.log"
# claude -p の標準出力（生JSON）+ サマリ行を1タスクにつき2行追記するログ
RAW_LOG="ai_generated/intermediate_files/from_source/progress/comment_writer_${WORKER_ID}_raw.jsonl"
# turnごとのEdit差分ログ（inotifywait経由）
DIFF_LOG="ai_generated/intermediate_files/from_source/progress/comment_writer_${WORKER_ID}_diffs.log"
# 一時ファイル。毎回のclaude -p実行で上書きされる。エラー内容はlog関数経由でLOGに記録されるため、ERRLOGは最新1回分のみ保持すれば十分
ERRLOG="ai_generated/intermediate_files/from_source/progress/comment_writer_${WORKER_ID}_err.log"
# 暫定値。セクション7.17参照。V3で実測して調整する
MAX_TURNS=100
TIMEOUT_SEC=900
MAX_CONSECUTIVE_RATE_LIMIT=5
# Invalid API key検出時の待機秒数（レートリミットウインドウのリセットを待つ）
INVALID_API_KEY_WAIT_SEC=300

# === カウンタ ===
DONE_COUNT=0
FAIL_COUNT=0
RELEASE_COUNT=0
CONSECUTIVE_RATE_LIMIT=0
CONFIG_ERROR_FLAG=false
# case 4（JSON経由の429検出による即停止）が発動したかを追跡するフラグ。
# サマリの RATE_LIMIT_EXIT に反映し、orchestrator側で長めbackoffを取らせるため。
# プラン7.24（rate_limit即停止 → 長くbackoff方針）の整合性確保。
RATE_LIMIT_IMMEDIATE_STOP_FLAG=false

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Worker $WORKER_ID] $*" >> "$LOG"
}

# === claude -p でファイルを処理 ===
# 戻り値:
#   0 = 成功
#   1 = リトライ不可の失敗（fail [!]）
#   2 = リトライ可能な失敗（release [ ] + backoff）
#   3 = 設定エラー（ワーカー終了）
#   4 = rate_limit（429）検出 → release [ ] + 即停止（5hウインドウ超過は短時間で回復しない）
process_file() {
  local TASK="$1"
  local RESULT
  local EXIT_CODE
  local PREV_FILE="${TASK}.prev"
  local WATCHER_PID=""
  local READER_PID=""
  local FIFO_DIR=""

  log "START $TASK"

  # === turnごとのEdit差分ログ（inotifywait） ===
  # inotify-toolsがインストールされていない場合はスキップ（差分ログなしで動作）
  # FIFO経由の2プロセス分離設計（plan: 7.25.2、M1対策）:
  #   inotifywait本体を直接バックグラウンド起動してPIDを明示管理。
  #   subshellパイプ（`( inotifywait | while done ) &`）方式だと、subshell kill時に
  #   パイプ内のinotifywaitが孤児化してinitにreparentされ残留する問題があったため、
  #   inotifywaitとdiff生成ループを分離しFIFOで連結する。
  #
  # ディレクトリ監視方式（8.5修正）:
  #   Claude CodeのEdit toolはatomic rename（一時ファイルに書き込み→mv）で更新する。
  #   ファイル直接監視のclose_writeではmvを検出できないため、
  #   ディレクトリをmoved_to+close_writeで監視し、ファイル名フィルタで対象を絞る。
  if command -v inotifywait >/dev/null 2>&1 && [ -f "$TASK" ]; then
    cp "$TASK" "$PREV_FILE" 2>/dev/null || true
    FIFO_DIR=$(mktemp -d)
    local FIFO="${FIFO_DIR}/events"
    mkfifo "$FIFO"

    # ディレクトリを監視（Edit toolはatomic rename=moved_toを使うため、ファイル直接監視では検出不可）
    local TASK_DIR
    TASK_DIR=$(dirname "$TASK")
    local TASK_BASENAME
    TASK_BASENAME=$(basename "$TASK")

    # ディレクトリを監視: moved_to（atomic rename）+ close_write（直接書き込み）を捕捉
    inotifywait -m -e moved_to -e close_write --format '%f %e' "$TASK_DIR" 2>/dev/null > "$FIFO" &
    WATCHER_PID=$!

    # diff生成ループ: ファイル名フィルタで対象ファイルのイベントのみ処理
    (
      EDIT_COUNT=0
      while read -r filename events; do
        if [ "$filename" = "$TASK_BASENAME" ]; then
          EDIT_COUNT=$((EDIT_COUNT + 1))
          echo "=== EDIT #${EDIT_COUNT} $(date '+%Y-%m-%d %H:%M:%S') $TASK ===" >> "$DIFF_LOG"
          diff -u "$PREV_FILE" "$TASK" >> "$DIFF_LOG" 2>/dev/null || true
          cp "$TASK" "$PREV_FILE" 2>/dev/null || true
        fi
      done < "$FIFO"
    ) &
    READER_PID=$!
  fi

  # claude -p 実行（JSONモード）
  # --bare: CLAUDE.md/hooks/skills/pluginsの自動ディスカバリをスキップ（起動高速化、トークン削減）
  # --settings: apiKeyHelperでCLAUDE_CODE_TOKEN（OAuthトークン）を渡す（--bareがOAuthを読まないため）
  RESULT=$(timeout "$TIMEOUT_SEC" claude -p \
    --bare \
    --settings "{\"apiKeyHelper\": \"echo $CLAUDE_CODE_TOKEN\"}" \
    --model sonnet \
    --max-turns "$MAX_TURNS" \
    --no-session-persistence \
    --allowedTools "Read Edit" \
    --disallowedTools "Bash Write Agent" \
    --output-format json \
    --system-prompt-file "$RULES_FILE" \
    "以下のファイルを読み込み、コメント付与ルールに従ってコメントを追加してください: $TASK" \
    2>"$ERRLOG") || EXIT_CODE=$?
  EXIT_CODE=${EXIT_CODE:-0}

  # === 監視停止・クリーンアップ ===
  # 順序: inotifywait を先にkill → FIFO側のwhileループは EOF で自然終了 → reader wait
  if [ -n "$WATCHER_PID" ]; then
    kill "$WATCHER_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true
  fi
  if [ -n "$READER_PID" ]; then
    wait "$READER_PID" 2>/dev/null || true
  fi
  if [ -n "$FIFO_DIR" ] && [ -d "$FIFO_DIR" ]; then
    rm -rf "$FIFO_DIR"
  fi
  rm -f "$PREV_FILE"

  # --- ケース: OS timeout ---
  if [ "$EXIT_CODE" -eq 124 ]; then
    log "TIMEOUT $TASK (${TIMEOUT_SEC}s)"
    return 1
  fi

  # --- ケース: EXIT_CODE≠0 ---
  # claude -p のJSONモードではmax-turns超過等でもEXIT_CODE=1を返すことがある（v2.1.96で確認）。
  # $RESULTにJSON出力が含まれている場合はJSON解析パスに進む。
  # JSON出力がない場合のみstderrを解析する。
  if [ "$EXIT_CODE" -ne 0 ]; then
    # $RESULTにJSONが含まれているか確認（"type":"result"が含まれるか）
    if echo "$RESULT" | grep -q '"type":"result"'; then
      # JSON出力あり → EXIT_CODE≠0でもJSON解析パスに進む（下のis_error判定で処理される）
      :
    else
      # JSON出力なし → stderrを解析
      local STDERR
      STDERR=$(cat "$ERRLOG" 2>/dev/null || echo "")

      # レートリミット検出
      if echo "$STDERR" | grep -qiE "rate|overload|529|429"; then
        log "RATE_LIMIT $TASK: $STDERR"
        return 2
      fi

      # ネットワークエラー検出
      if echo "$STDERR" | grep -qiE "API Error|connect|ECONNREFUSED"; then
        log "NETWORK_ERROR $TASK: $STDERR"
        return 2
      fi

      # 設定エラー検出（リカバリ不可、ワーカー終了すべき）
      if echo "$STDERR" | grep -qiE "cannot be used|not exist|not have access"; then
        log "CONFIG_ERROR $TASK: $STDERR"
        return 3
      fi

      # その他のエラー
      log "UNKNOWN_ERROR exit=$EXIT_CODE $TASK: $STDERR"
      return 1
    fi
  fi

  # --- ケース: EXIT_CODE=0 だが JSON の is_error=true ---
  local IS_ERROR TERMINAL_REASON COST DURATION NUM_TURNS RESULT_TEXT
  IS_ERROR=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_error',False))" 2>/dev/null || echo "Unknown")
  TERMINAL_REASON=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('terminal_reason',''))" 2>/dev/null || echo "")
  COST=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_cost_usd',0))" 2>/dev/null || echo "0")
  DURATION=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('duration_ms',0))" 2>/dev/null || echo "0")
  NUM_TURNS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('num_turns',0))" 2>/dev/null || echo "0")
  RESULT_TEXT=$(echo "$RESULT" | python3 -c "import sys,json; r=json.load(sys.stdin).get('result',''); print(r[:500] if isinstance(r,str) else str(r)[:500])" 2>/dev/null || echo "(parse failed)")

  # JSON解析失敗のガード（claude -pが空出力や不正JSONを返した場合）
  if [ "$IS_ERROR" != "True" ] && [ "$IS_ERROR" != "False" ]; then
    log "JSON_PARSE_ERROR is_error=$IS_ERROR $TASK"
    return 1
  fi

  if [ "$IS_ERROR" = "True" ]; then
    log "API_ERROR terminal=$TERMINAL_REASON cost=\$$COST duration=${DURATION}ms turns=$NUM_TURNS $TASK"
    log "API_ERROR_DETAIL result=$RESULT_TEXT"
    log "API_ERROR_JSON $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); [d.pop(k,None) for k in ['session_id']]; print(json.dumps(d,ensure_ascii=False))" 2>/dev/null || echo "(json dump failed)")"

    # === 生JSONログ（エラー時） ===
    # サマリ行 + 生JSON行を .jsonl に追記。デバッグ時の情報欠損を防ぐ
    # サマリ値は python3 json.dumps() でエスケープしJSON壊れを防ぐ
    # ($TASK 等にダブルクォート・バックスラッシュ・改行が含まれる可能性に備える)
    python3 -c 'import json,sys; print(json.dumps({"summary": sys.argv[1]}))' \
      "API_ERROR terminal=$TERMINAL_REASON cost=\$$COST duration=${DURATION}ms turns=$NUM_TURNS $TASK" \
      >> "$RAW_LOG"
    printf '%s\n' "$RESULT" >> "$RAW_LOG"

    # --- 429 rate_limit_error 検出 → ワーカー即停止 ---
    # 5hウインドウの超過は短時間で回復しない。即停止してファイルをreleaseする
    # （セクション7.24.1参照）
    if echo "$RESULT_TEXT" | grep -qiE "rate_limit|429"; then
      log "RATE_LIMIT_STOP $TASK: $RESULT_TEXT"
      return 4
    fi

    # --- Invalid API key 検出 → 5分sleep + リトライ ---
    # トークンブロックは一時的。レートリミットウインドウのリセットで自動解除される
    # （セクション7.23参照）
    if echo "$RESULT_TEXT" | grep -qi "Invalid API key"; then
      log "INVALID_API_KEY $TASK: sleeping ${INVALID_API_KEY_WAIT_SEC}s before retry"
      sleep "$INVALID_API_KEY_WAIT_SEC"
      return 2
    fi

    return 1
  fi

  # --- ケース: 正常終了 ---
  local SUMMARY_MSG
  if git diff --quiet "$TASK" 2>/dev/null; then
    SUMMARY_MSG="DONE_NO_CHANGE cost=\$$COST duration=${DURATION}ms turns=$NUM_TURNS $TASK"
  else
    SUMMARY_MSG="DONE cost=\$$COST duration=${DURATION}ms turns=$NUM_TURNS $TASK"
  fi
  log "$SUMMARY_MSG"

  # === 生JSONログ（成功時） ===
  # サマリ値は python3 json.dumps() でエスケープしJSON壊れを防ぐ
  # ($TASK 等にダブルクォート・バックスラッシュ・改行が含まれる可能性に備える)
  python3 -c 'import json,sys; print(json.dumps({"summary": sys.argv[1]}))' "$SUMMARY_MSG" >> "$RAW_LOG"
  printf '%s\n' "$RESULT" >> "$RAW_LOG"

  return 0
}

# === メインループ ===
log "=== Worker $WORKER_ID started ==="
log "CONFIG: TODO=$TODO RULES_FILE=$RULES_FILE MAX_TURNS=$MAX_TURNS TIMEOUT_SEC=$TIMEOUT_SEC MAX_CONSECUTIVE_RATE_LIMIT=$MAX_CONSECUTIVE_RATE_LIMIT"

while TASK=$("$SCRIPT" next "$TODO"); do
  # R2-1対策: set -e でスクリプトが終了しないようerr trapを回避
  process_file "$TASK" && PROCESS_RESULT=0 || PROCESS_RESULT=$?

  case $PROCESS_RESULT in
    0)
      # 成功 → done [x]
      if "$SCRIPT" done "$TODO" "$TASK"; then
        DONE_COUNT=$((DONE_COUNT + 1))
      else
        log "DONE_CMD_FAILED $TASK"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      CONSECUTIVE_RATE_LIMIT=0
      ;;

    1)
      # リトライ不可の失敗 → fail [!]
      "$SCRIPT" fail "$TODO" "$TASK" || true
      FAIL_COUNT=$((FAIL_COUNT + 1))
      CONSECUTIVE_RATE_LIMIT=0
      ;;

    3)
      # 設定エラー → fail [!] + ワーカー終了
      "$SCRIPT" fail "$TODO" "$TASK" || true
      FAIL_COUNT=$((FAIL_COUNT + 1))
      CONFIG_ERROR_FLAG=true
      log "CONFIG_ERROR detected, worker exiting"
      break
      ;;

    2)
      # リトライ可能な失敗 → release [ ]
      "$SCRIPT" release "$TODO" "$TASK" || true
      RELEASE_COUNT=$((RELEASE_COUNT + 1))
      CONSECUTIVE_RATE_LIMIT=$((CONSECUTIVE_RATE_LIMIT + 1))

      if [ "$CONSECUTIVE_RATE_LIMIT" -ge "$MAX_CONSECUTIVE_RATE_LIMIT" ]; then
        log "RATE_LIMIT_EXIT after ${MAX_CONSECUTIVE_RATE_LIMIT} consecutive failures"
        break
      fi

      # 追加backoff（process_file内で待機済みの場合あり。ここでは連続回数に応じた追加待機のみ）
      # 分間レートリミット(RPM/ITPM/OTPM)はトークンバケットで補充されるため、長めに待つ
      WAIT=$((30 * CONSECUTIVE_RATE_LIMIT))
      log "BACKOFF sleeping additional ${WAIT}s (total consecutive=$CONSECUTIVE_RATE_LIMIT)"
      sleep "$WAIT"
      ;;

    4)
      # rate_limit（429）検出 → release [ ] + 即停止
      # 5hウインドウの超過は短時間で回復しない。次ラウンドに委ねる
      # （セクション7.24参照）
      # フラグを立ててサマリのRATE_LIMIT_EXIT=trueをorchestratorに通知し、
      # 次ラウンドbackoffをBACKOFF_RATE_LIMIT_SEC（120秒）に切り替えさせる
      "$SCRIPT" release "$TODO" "$TASK" || true
      RELEASE_COUNT=$((RELEASE_COUNT + 1))
      RATE_LIMIT_IMMEDIATE_STOP_FLAG=true
      log "RATE_LIMIT_IMMEDIATE_STOP $TASK"
      break
      ;;
  esac
done

# === 完了サマリ（標準出力 → comment-orchestrator.shがファイルにキャプチャする） ===
log "=== Worker $WORKER_ID finished: done=$DONE_COUNT fail=$FAIL_COUNT release=$RELEASE_COUNT ==="

# RATE_LIMIT_EXIT は2経路で立つ:
#   (1) case 2 が MAX_CONSECUTIVE_RATE_LIMIT 連続発生（stderr経由のretryable長期化）
#   (2) case 4 が1回でも発動（JSON経由の429検出による即停止、プラン7.24方針）
cat <<EOF
WORKER_ID=$WORKER_ID
DONE=$DONE_COUNT
FAIL=$FAIL_COUNT
RELEASE=$RELEASE_COUNT
RATE_LIMIT_EXIT=$( ( [ "$CONSECUTIVE_RATE_LIMIT" -ge "$MAX_CONSECUTIVE_RATE_LIMIT" ] || [ "$RATE_LIMIT_IMMEDIATE_STOP_FLAG" = "true" ] ) && echo "true" || echo "false" )
CONFIG_ERROR=$CONFIG_ERROR_FLAG
EOF
