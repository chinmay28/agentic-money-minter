#!/usr/bin/env bash
# Send stdin to a Telegram chat as plain-text messages.
#
# Usage:   scripts/telegram-send.sh < report.txt
# Env:     TELEGRAM_BOT_TOKEN  bot token from @BotFather (required, never printed)
#          TELEGRAM_CHAT_ID    chat to send to (required)
#          TELEGRAM_API_URL    API base, default https://api.telegram.org (tests override it)
#          TELEGRAM_MAX_CHARS  max characters per message, default 4000 (Telegram's limit is 4096)
#
# Input is split on line boundaries into messages of at most TELEGRAM_MAX_CHARS
# characters; a single longer line is hard-split. Messages are sent in order.
# Exit status: 0 all sent, 1 a message was rejected, 2 bad config or empty input.
set -euo pipefail

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "telegram-send: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set" >&2
  exit 2
fi
api="${TELEGRAM_API_URL:-https://api.telegram.org}"
max="${TELEGRAM_MAX_CHARS:-4000}"

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT

LC_ALL=C.UTF-8 awk -v max="$max" -v dir="$dir" '
  function emit(s,   f) { f = sprintf("%s/part-%04d", dir, n++); printf "%s", s > f; close(f) }
  function flush() { if (cur != "") { emit(cur); cur = "" } }
  {
    line = $0
    while (length(line) > max) { flush(); emit(substr(line, 1, max)); line = substr(line, max + 1) }
    if (cur != "" && length(cur) + 1 + length(line) > max) flush()
    cur = (cur == "") ? line : cur "\n" line
  }
  END { flush() }
'

parts=("$dir"/part-*)
if [[ ! -e "${parts[0]}" ]]; then
  echo "telegram-send: nothing to send (empty input)" >&2
  exit 2
fi

i=0
for part in "${parts[@]}"; do
  i=$((i + 1))
  code="$(curl -sS -o "$dir/response" -w '%{http_code}' -X POST \
    "$api/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text@${part}" \
    --data "disable_web_page_preview=true" 2>"$dir/curl-err")" || code="000"
  if [[ "$code" != "200" ]]; then
    # Report Telegram's error description or curl's error, never the URL (it holds the token).
    reason="$(sed -n 's/.*"description": *"\([^"]*\)".*/\1/p' "$dir/response" 2>/dev/null || true)"
    [[ -z "$reason" ]] && reason="$(sed "s|bot${TELEGRAM_BOT_TOKEN}|bot<redacted>|g" "$dir/curl-err" 2>/dev/null || true)"
    echo "telegram-send: message $i/${#parts[@]} failed (HTTP $code): ${reason:-no details}" >&2
    exit 1
  fi
done
echo "telegram-send: sent ${#parts[@]} message(s)"
