#!/usr/bin/env bash
# Append stdin to today's Telegram trading log: one message per day, one timestamped entry per run.
#
# Usage:   scripts/telegram-log.sh < entry.txt
# Env:     TELEGRAM_BOT_TOKEN  bot token from @BotFather (required, never printed)
#          TELEGRAM_CHAT_ID    chat to log to (required)
#          TELEGRAM_API_URL    API base, default https://api.telegram.org (tests override it)
#          TELEGRAM_MAX_CHARS  max characters per message, default 4000 (Telegram's limit is 4096)
#          TELEGRAM_NOW        current time as Unix seconds, default now (tests override it)
#
# A log day runs from 6:00 AM PT to 5:59 AM PT the next morning. Its log is a
# message whose first line is the title "📒 Trading log · Tue Oct 6"; the bot
# keeps it pinned, and the pin is how the next run finds it (runs keep no state).
# Each run appends "── 3:48 PM PT ──" plus stdin by editing that message, so
# updates arrive silently. A new message is sent (and pinned, replacing the
# previous log's pin) for the day's first entry, and as "(part N)" when an entry
# would push the message past TELEGRAM_MAX_CHARS or the log can't be read or
# edited — an entry is never dropped, at worst the day spans more messages.
#
# Exit status: 0 entry delivered (problems that only cost a pin print
#              "telegram-log: warning: ..." on stderr), 1 Telegram rejected the
#              entry or is unreachable, 2 bad config, empty input or jq missing.
set -euo pipefail
export LC_ALL=C.UTF-8

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "telegram-log: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set" >&2
  exit 2
fi
if ! command -v jq >/dev/null; then
  echo "telegram-log: jq is required" >&2
  exit 2
fi
api="${TELEGRAM_API_URL:-https://api.telegram.org}"
max="${TELEGRAM_MAX_CHARS:-4000}"
now="${TELEGRAM_NOW:-$(date +%s)}"
day_start=$((6 * 3600))
prefix="📒 Trading log · "

input="$(cat)"
if [[ -z "${input//[[:space:]]/}" ]]; then
  echo "telegram-log: nothing to send (empty input)" >&2
  exit 2
fi

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT

pt() { TZ=America/Los_Angeles date -d "@$1" "$2"; }
day_key() { pt $(($1 - day_start)) +%F; }
warn() { echo "telegram-log: warning: $*" >&2; }

today="$(day_key "$now")"
title="$prefix$(pt $((now - day_start)) '+%a %b %-d')"
entry="── $(pt "$now" '+%-I:%M %p') PT ──"$'\n'"$input"

# call METHOD [curl args...]: POSTs to the Bot API; the body lands in $dir/response.
# On failure returns 1 with $err set to Telegram's description or curl's error, never the URL (it holds the token).
err=""
call() {
  local method="$1" code reason
  shift
  code="$(curl -sS -o "$dir/response" -w '%{http_code}' -X POST \
    "$api/bot${TELEGRAM_BOT_TOKEN}/$method" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" "$@" 2>"$dir/curl-err")" || code="000"
  [[ "$code" == "200" ]] && return 0
  reason="$(jq -r '.description // empty' "$dir/response" 2>/dev/null || true)"
  [[ -z "$reason" ]] && reason="$(sed "s|bot${TELEGRAM_BOT_TOKEN}|bot<redacted>|g" "$dir/curl-err" 2>/dev/null || true)"
  err="$method failed (HTTP $code): ${reason:-no details}"
  return 1
}

# Find the pinned log: today's (to append to) and any day's (to unpin when a new one replaces it).
log_id="" log_text="" part=0 old_pin=""
if call getChat; then
  pin_id="$(jq -r '.result.pinned_message.message_id // empty' "$dir/response")"
  pin_text="$(jq -r '.result.pinned_message.text // empty' "$dir/response")"
  pin_date="$(jq -r '.result.pinned_message.date // 0' "$dir/response")"
  if [[ -n "$pin_id" && "$pin_text" == "$prefix"* ]]; then
    old_pin="$pin_id"
    first="${pin_text%%$'\n'*}"
    if [[ "$(day_key "$pin_date")" == "$today" && "$first" =~ ^"$title"(" (part "([0-9]+)")")?$ ]]; then
      log_id="$pin_id" log_text="$pin_text" part="${BASH_REMATCH[2]:-1}"
    fi
  fi
else
  warn "could not read the pinned log ($err); starting a new message"
fi

# Append to today's log when it fits.
if [[ -n "$log_id" ]]; then
  printf '%s\n\n%s' "$log_text" "$entry" > "$dir/text"
  if (( $(wc -m < "$dir/text") <= max )); then
    if call editMessageText --data "message_id=$log_id" --data-urlencode "text@$dir/text"; then
      echo "telegram-log: appended to $title"
      exit 0
    fi
    warn "could not edit today's log ($err); starting a new part"
  fi
fi

# Otherwise start a new message (several if the entry alone is too long), each titled so the next run can find it.
# awk may count bytes rather than characters, which only makes chunks smaller.
room=$((max - ${#title} - 14)) # header is title + " (part NNN)" + blank line
printf '%s\n' "$entry" | awk -v max="$room" -v dir="$dir" '
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
sent_id=""
for chunk in "$dir"/part-*; do
  part=$((part + 1))
  header="$title"
  (( part > 1 )) && header="$title (part $part)"
  { printf '%s\n\n' "$header"; cat "$chunk"; } > "$dir/text"
  if ! call sendMessage --data-urlencode "text@$dir/text" --data "disable_web_page_preview=true"; then
    echo "telegram-log: $err" >&2
    exit 1
  fi
  sent_id="$(jq -r '.result.message_id // empty' "$dir/response")"
  echo "telegram-log: sent $header"
done

if [[ -z "$sent_id" ]]; then
  warn "Telegram returned no message_id; the next run will start a new message"
elif ! call pinChatMessage --data "message_id=$sent_id" --data "disable_notification=true"; then
  warn "could not pin the log ($err); the next run will start a new message"
elif [[ -n "$old_pin" ]] && ! call unpinChatMessage --data "message_id=$old_pin"; then
  warn "could not unpin the previous log ($err)"
fi
exit 0
