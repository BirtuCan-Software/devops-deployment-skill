#!/usr/bin/env bash
# ==============================================================================
# Script: telegram-notify.sh
# Purpose: Orchestrates atomic Start-Delete-Replace deployment notifications via
#          the official Telegram Bot API matching exact ForgeDocs styling & structure.
# Compatibility: POSIX bash, curl. Non-blocking (never breaks CI on failure).
# ==============================================================================

set -uo pipefail

ACTION="${1:-}"

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
RAW_THREAD_ID="${TELEGRAM_MESSAGE_THREAD_ID:-}"

# Guard: If Telegram credentials are missing, log gracefully and exit 0
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "⚠️ Telegram secrets (TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID) not configured. Skipping notification."
  exit 0
fi

API_URL="https://api.telegram.org/bot${BOT_TOKEN}"

# Strict HTML escaping function: handles &, <, >
html_escape() {
  printf '%s' "${1:-}" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Context variables with safe fallbacks matching exact ForgeDocs deploy.yml conventions
REPO=$(html_escape "${GITHUB_REPOSITORY:-local/repo}")
BRANCH=$(html_escape "${GITHUB_REF_NAME:-main}")
ENV_NAME="${GITHUB_ENVIRONMENT:-${ENVIRONMENT_NAME:-}}"
if [ -z "$ENV_NAME" ]; then
  if [ "$BRANCH" = "main" ]; then
    ENV_NAME="production"
  else
    ENV_NAME="staging"
  fi
fi

ACTOR=$(html_escape "${GITHUB_TRIGGERING_ACTOR:-${GITHUB_ACTOR:-developer}}")
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
REPO_NAME="${GITHUB_REPOSITORY:-local/repo}"
RUN_ID="${GITHUB_RUN_ID:-}"
RUN_NUM="${GITHUB_RUN_NUMBER:-1}"
RUN_URL="${SERVER_URL}/${REPO_NAME}/actions/runs/${RUN_ID}"

COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "${GITHUB_SHA:0:7}")
RAW_COMMIT_MSG="${COMMIT_MESSAGE:-$(git log -1 --pretty=format:'%s' 2>/dev/null || echo 'Manual Trigger')}"
COMMIT_MSG_ESCAPED=$(echo "$RAW_COMMIT_MSG" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

# Sanitize Thread ID
THREAD_ID=$(echo "$RAW_THREAD_ID" | tr -d '[:space:]')
EXTRA_ARGS=()
if [ -n "$THREAD_ID" ] && [ "$THREAD_ID" != "0" ]; then
  EXTRA_ARGS+=(--data-urlencode "message_thread_id=${THREAD_ID}")
fi

# Helper: Send message using curl with --data-urlencode matching deploy.yml
send_telegram_msg() {
  local msg_text="$1"
  curl -s -S -X POST "${API_URL}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" \
    "${EXTRA_ARGS[@]}" \
    --data-urlencode "text=${msg_text}" || true
}

# Helper: Delete message using curl matching deploy.yml
delete_telegram_msg() {
  local msg_id="$1"
  if [ -n "$msg_id" ] && [ "$msg_id" != "0" ] && [ "$msg_id" != "null" ]; then
    curl -s -S -X POST "${API_URL}/deleteMessage" \
      --data-urlencode "chat_id=${CHAT_ID}" \
      --data-urlencode "message_id=${msg_id}" >/dev/null 2>&1 || true
  fi
}

case "$ACTION" in
  start)
    MESSAGE="🚀 <b>Deployment Started</b>"$'\n\n'
    MESSAGE+="<blockquote>"
    MESSAGE+="📦 <b>Repository:</b> <code>${REPO}</code>"$'\n'
    MESSAGE+="🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ENV_NAME})"$'\n'
    MESSAGE+="👤 <b>Triggered By:</b> ${ACTOR}"$'\n'
    MESSAGE+="📝 <b>Commit:</b> <code>${COMMIT_HASH}</code> — ${COMMIT_MSG_ESCAPED}"
    MESSAGE+="</blockquote>"$'\n\n'
    MESSAGE+="🔗 <a href=\"${RUN_URL}\"><b>View Actions Run #${RUN_NUM} →</b></a>"

    RESP=$(send_telegram_msg "$MESSAGE")
    MSG_ID=$(echo "$RESP" | grep -o '"message_id":[0-9]*' | cut -d: -f2 | head -n 1)

    if [ -n "$MSG_ID" ]; then
      echo "TELEGRAM_STARTED_MSG_ID=$MSG_ID"
      if [ -n "${GITHUB_ENV:-}" ]; then
        echo "TELEGRAM_STARTED_MSG_ID=$MSG_ID" >> "$GITHUB_ENV"
      fi
      if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "message_id=$MSG_ID" >> "$GITHUB_OUTPUT"
      fi
    fi

    NOW_TS=$(date +%s)
    if [ -n "${GITHUB_ENV:-}" ]; then
      echo "DEPLOY_START_TIME=$NOW_TS" >> "$GITHUB_ENV"
    fi
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "start_time=$NOW_TS" >> "$GITHUB_OUTPUT"
    fi
    ;;

  finish)
    STATUS="${2:-success}"
    STARTED_MSG_ID="${3:-${TELEGRAM_STARTED_MSG_ID:-}}"
    START_TIME="${4:-${DEPLOY_START_TIME:-}}"

    # 1. Delete previous 'Started' notification to keep topic clean
    if [ -n "$STARTED_MSG_ID" ]; then
      delete_telegram_msg "$STARTED_MSG_ID"
    fi

    # 2. Calculate duration line exactly matching deploy.yml
    DURATION_LINE=""
    if [ -n "$START_TIME" ]; then
      if [[ "$START_TIME" =~ ^[0-9]+$ ]] && [ "$START_TIME" -gt 1000000000 ]; then
        END_TIME=$(date +%s)
        DURATION=$(( END_TIME - START_TIME ))
        MINS=$(( DURATION / 60 ))
        SECS=$(( DURATION % 60 ))
        if [ $MINS -gt 0 ]; then
          DURATION_LINE="⏱️ <b>Duration:</b> ${MINS}m ${SECS}s"$'\n'
        else
          DURATION_LINE="⏱️ <b>Duration:</b> ${SECS}s"$'\n'
        fi
      else
        DURATION_LINE="⏱️ <b>Duration:</b> ${START_TIME}"$'\n'
      fi
    elif [ -n "${DEPLOY_START_TIME:-}" ]; then
      END_TIME=$(date +%s)
      DURATION=$(( END_TIME - DEPLOY_START_TIME ))
      MINS=$(( DURATION / 60 ))
      SECS=$(( DURATION % 60 ))
      if [ $MINS -gt 0 ]; then
        DURATION_LINE="⏱️ <b>Duration:</b> ${MINS}m ${SECS}s"$'\n'
      else
        DURATION_LINE="⏱️ <b>Duration:</b> ${SECS}s"$'\n'
      fi
    fi

    # 3. Formulate message by exact status
    if [ "$STATUS" = "success" ]; then
      MESSAGE="✅ <b>Deployment Successful</b>"$'\n\n'
      MESSAGE+="<blockquote>"
      MESSAGE+="📦 <b>Repository:</b> <code>${REPO}</code>"$'\n'
      MESSAGE+="🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ENV_NAME})"$'\n'
      MESSAGE+="👤 <b>Triggered By:</b> ${ACTOR}"$'\n'
      MESSAGE+="📝 <b>Commit:</b> <code>${COMMIT_HASH}</code> — ${COMMIT_MSG_ESCAPED}"$'\n'
      MESSAGE+="${DURATION_LINE%?}"
      MESSAGE+="</blockquote>"$'\n\n'
      MESSAGE+="🔗 <a href=\"${RUN_URL}\"><b>View Actions Run #${RUN_NUM} →</b></a>"
    elif [ "$STATUS" = "failure" ]; then
      MESSAGE="❌ <b>Deployment Failed</b>"$'\n\n'
      MESSAGE+="<blockquote>"
      MESSAGE+="📦 <b>Repository:</b> <code>${REPO}</code>"$'\n'
      MESSAGE+="🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ENV_NAME})"$'\n'
      MESSAGE+="👤 <b>Triggered By:</b> ${ACTOR}"$'\n'
      MESSAGE+="📝 <b>Commit:</b> <code>${COMMIT_HASH}</code> — ${COMMIT_MSG_ESCAPED}"$'\n'
      MESSAGE+="${DURATION_LINE%?}"
      MESSAGE+="</blockquote>"$'\n\n'
      MESSAGE+="🔗 <a href=\"${RUN_URL}\"><b>View Failure Logs #${RUN_NUM} →</b></a>"
    elif [ "$STATUS" = "cancelled" ]; then
      MESSAGE="⚠️ <b>Deployment Cancelled</b>"$'\n\n'
      MESSAGE+="<blockquote>"
      MESSAGE+="📦 <b>Repository:</b> <code>${REPO}</code>"$'\n'
      MESSAGE+="🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ENV_NAME})"$'\n'
      MESSAGE+="👤 <b>Triggered By:</b> ${ACTOR}"$'\n'
      MESSAGE+="📝 <b>Commit:</b> <code>${COMMIT_HASH}</code> — ${COMMIT_MSG_ESCAPED}"$'\n'
      MESSAGE+="${DURATION_LINE%?}"
      MESSAGE+="</blockquote>"$'\n\n'
      MESSAGE+="🔗 <a href=\"${RUN_URL}\"><b>View Actions Run #${RUN_NUM} →</b></a>"
    fi

    send_telegram_msg "$MESSAGE" >/dev/null
    echo "Final notification ($STATUS) sent."
    ;;

  delete)
    MSG_ID="${2:-}"
    delete_telegram_msg "$MSG_ID"
    ;;

  *)
    echo "Usage: $0 {start|finish [status] [started_msg_id] [start_time]|delete [msg_id]}"
    exit 1
    ;;
esac

exit 0
