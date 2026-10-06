#!/usr/bin/env bash
# Tests for telegram-log.sh against a local stub of the Telegram Bot API.
# Usage: scripts/telegram-log_test.sh
set -euo pipefail
cd "$(dirname "$0")"
export LC_ALL=C.UTF-8

work="$(mktemp -d)"
trap 'kill "$stub_pid" 2>/dev/null || true; rm -rf "$work"' EXIT

# Stub chat: keeps messages and the pin list in memory and dumps them to $work/state.json
# after every request. A message's date is read from $work/now. Writing a method name
# to $work/fail makes that method return 400; chat_id "bad" fails every method.
cat > "$work/stub.py" <<'PY'
import http.server, json, os, sys, urllib.parse
out = sys.argv[1]
state = {"messages": {}, "pins": [], "calls": []}
def now(): return int(open(os.path.join(out, "now")).read())
def failing():
    p = os.path.join(out, "fail")
    return open(p).read().split() if os.path.exists(p) else []
class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, obj):
        self.send_response(code); self.end_headers(); self.wfile.write(json.dumps(obj).encode())
    def do_POST(self):
        method = self.path.rsplit("/", 1)[1]
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        form = {k: v[0] for k, v in urllib.parse.parse_qs(body, keep_blank_values=True).items()}
        state["calls"].append(method)
        msgs, pins = state["messages"], state["pins"]
        if form["chat_id"] == "bad" or method in failing():
            res = (400, {"ok": False, "description": "Bad Request: chat not found"})
        elif method == "getChat":
            chat = {"id": 42}
            if pins:  # like Telegram: the most recent pinned message by sending date
                mid = max(pins, key=lambda m: (msgs[m]["date"], int(m)))
                chat["pinned_message"] = {"message_id": int(mid), **msgs[mid]}
            res = (200, {"ok": True, "result": chat})
        elif method == "sendMessage":
            mid = str(len(msgs) + 1)
            msgs[mid] = {"text": form["text"], "date": now()}
            res = (200, {"ok": True, "result": {"message_id": int(mid)}})
        elif method == "editMessageText":
            msgs[form["message_id"]]["text"] = form["text"]
            res = (200, {"ok": True, "result": {}})
        elif method == "pinChatMessage":
            pins.append(form["message_id"]); res = (200, {"ok": True, "result": True})
        elif method == "unpinChatMessage":
            pins.remove(form["message_id"]); res = (200, {"ok": True, "result": True})
        else:
            res = (404, {"ok": False, "description": "Not Found"})
        json.dump(state, open(os.path.join(out, "state.json"), "w"))
        self.reply(*res)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(out, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
PY
reset() { # fresh chat: restarts the stub
  [[ -n "${stub_pid:-}" ]] && { kill "$stub_pid"; wait "$stub_pid" 2>/dev/null || true; }
  rm -f "$work"/{port,fail,state.json}
  python3 "$work/stub.py" "$work" & stub_pid=$!
  for _ in $(seq 50); do [[ -s "$work/port" ]] && break; sleep 0.1; done
  export TELEGRAM_API_URL="http://127.0.0.1:$(cat "$work/port")"
}
at() { # at "2026-10-06 15:48" TEXT: runs the script at that PT time with TEXT on stdin
  TELEGRAM_NOW="$(TZ=America/Los_Angeles date -d "$1" +%s)"
  export TELEGRAM_NOW; echo "$TELEGRAM_NOW" > "$work/now"
  printf '%s\n' "$2" | ./telegram-log.sh
}
api() { # api METHOD key=value...: calls the stub directly, as the user's own client would
  local args=(--data-urlencode "chat_id=42") kv
  for kv in "${@:2}"; do args+=(--data-urlencode "$kv"); done
  curl -sS -o /dev/null -X POST "$TELEGRAM_API_URL/botX/$1" "${args[@]}"
}
q() { jq -r "$1" "$work/state.json"; }
msg() { q ".messages[\"$1\"].text"; }
count() { q '.messages | length'; }
pinned() { q '.pins | join(",")'; }
xs() { printf "$1%.0s" $(seq "$2"); }

export NO_PROXY="127.0.0.1" no_proxy="127.0.0.1"
export TELEGRAM_BOT_TOKEN="123:SECRET-TOKEN" TELEGRAM_CHAT_ID="42"

fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
nl=$'\n'

reset; at "2026-10-06 06:18" "XLK: closed${nl}BTC: flat" >/dev/null
check "first run of the day sends a titled, timestamped message" \
  '[[ $(count) == 1 && "$(msg 1)" == "📒 Trading log · Tue Oct 6${nl}${nl}── 6:18 AM PT ──${nl}XLK: closed${nl}BTC: flat" ]]'
check "and pins it" '[[ $(pinned) == 1 ]]'

at "2026-10-06 15:48" "BTC: bought" >/dev/null
check "later run the same day appends to the same message" \
  '[[ $(count) == 1 && "$(msg 1)" == *"BTC: flat${nl}${nl}── 3:48 PM PT ──${nl}BTC: bought" ]]'
check "appending edits, never sends" '[[ $(q "[.calls[] | select(. == \"sendMessage\")] | length") == 1 ]]'

at "2026-10-07 05:48" "BTC: sold" >/dev/null
check "run before 6 AM belongs to the previous day" '[[ $(count) == 1 && "$(msg 1)" == *"── 5:48 AM PT ──${nl}BTC: sold" ]]'

at "2026-10-07 06:18" "BTC: flat again" >/dev/null
check "first run after 6 AM starts a new day" \
  '[[ $(count) == 2 && "$(msg 2)" == "📒 Trading log · Wed Oct 7${nl}${nl}── 6:18 AM PT ──${nl}BTC: flat again" ]]'
check "new day is pinned and the old one unpinned" '[[ $(pinned) == 2 ]]'
check "previous day's log is left as it was" '[[ "$(msg 1)" == *"BTC: sold" ]]'

reset; export TELEGRAM_MAX_CHARS=140
at "2026-10-06 07:18" "$(xs x 60)" >/dev/null
at "2026-10-06 07:48" "$(xs y 60)" >/dev/null
check "entry that would overflow starts part 2" \
  '[[ $(count) == 2 && "$(msg 2)" == "📒 Trading log · Tue Oct 6 (part 2)${nl}${nl}── 7:48 AM PT ──${nl}$(xs y 60)" ]]'
check "part 2 replaces part 1 as the pin" '[[ $(pinned) == 2 ]]'
at "2026-10-06 08:18" "z" >/dev/null
check "next run appends to part 2" '[[ $(count) == 2 && "$(msg 2)" == *"${nl}${nl}── 8:18 AM PT ──${nl}z" ]]'

reset; at "2026-10-06 09:18" "$(seq 1 80)" >/dev/null
check "entry longer than a message is split into titled parts" \
  '[[ $(count) -gt 1 && "$(msg 1)" == "📒 Trading log · Tue Oct 6${nl}"* && "$(msg 2)" == "📒 Trading log · Tue Oct 6 (part 2)${nl}"* ]]'
longest=0; for i in $(seq 1 "$(count)"); do n=$(msg "$i" | wc -m); (( n > longest )) && longest=$n; done
check "every part within limit" '[[ $longest -le 140 ]]'
check "parts keep every line in order" \
  '[[ "$(for i in $(seq 1 "$(count)"); do msg "$i" | tail -n +3; done | grep -v "──")" == "$(seq 1 80)" ]]'
check "last part is pinned" '[[ $(pinned) == $(count) ]]'
unset TELEGRAM_MAX_CHARS

reset; at "2026-10-06 10:18" "first" >/dev/null
echo editMessageText > "$work/fail"
err="$(at "2026-10-06 10:48" "second" 2>&1 >/dev/null)"; rc=$?
check "failed edit starts a new part instead of dropping the entry" \
  '[[ $rc == 0 && $(count) == 2 && "$(msg 2)" == *"(part 2)"*second ]]'
check "and warns" '[[ "$err" == *"warning: could not edit"* ]]'

reset; echo getChat > "$work/fail"
err="$(at "2026-10-06 11:18" "entry" 2>&1 >/dev/null)"; rc=$?
check "unreadable pin still delivers the entry" '[[ $rc == 0 && $(count) == 1 && "$(msg 1)" == *entry ]]'
check "and warns" '[[ "$err" == *"warning: could not read"* ]]'

reset; echo pinChatMessage > "$work/fail"
err="$(at "2026-10-06 11:18" "entry" 2>&1 >/dev/null)"; rc=$?
check "failed pin still exits 0 with a warning" '[[ $rc == 0 && $(count) == 1 && "$err" == *"warning: could not pin"* ]]'

reset; at "2026-10-06 12:18" "log" >/dev/null
api sendMessage "text=remember the milk"; api pinChatMessage message_id=2
at "2026-10-06 12:48" "more" >/dev/null
check "a pinned message without the log title is never edited" \
  '[[ "$(msg 2)" == "remember the milk" && "$(msg 3)" == "📒 Trading log · Tue Oct 6${nl}"*more ]]'
check "nor unpinned" '[[ $(pinned) == 1,2,3 ]]'

reset; at "2026-10-06 13:18" "é€ unicode ⚠️" >/dev/null
check "unicode passes through" '[[ "$(msg 1)" == *"é€ unicode ⚠️" ]]'

set +e
echo hi | TELEGRAM_BOT_TOKEN= ./telegram-log.sh 2>/dev/null; rc=$?
check "missing token exits 2" '[[ $rc == 2 ]]'
./telegram-log.sh < /dev/null 2>/dev/null; rc=$?
check "empty input exits 2" '[[ $rc == 2 ]]'
printf ' \n\n' | ./telegram-log.sh 2>/dev/null; rc=$?
check "blank input exits 2" '[[ $rc == 2 ]]'
err="$(echo hi | TELEGRAM_CHAT_ID=bad ./telegram-log.sh 2>&1 >/dev/null)"; rc=$?
check "rejected message exits 1" '[[ $rc == 1 ]]'
check "error shows Telegram description" '[[ "$err" == *"chat not found"* ]]'
check "error never shows the token" '[[ "$err" != *SECRET-TOKEN* ]]'
err="$(echo hi | TELEGRAM_API_URL=http://127.0.0.1:1 ./telegram-log.sh 2>&1 >/dev/null)"; rc=$?
check "network failure exits 1 without the token" '[[ $rc == 1 && "$err" != *SECRET-TOKEN* ]]'
set -e

[[ $fails == 0 ]] && echo "all tests passed" || { echo "$fails test(s) failed"; exit 1; }
