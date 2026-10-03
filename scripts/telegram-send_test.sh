#!/usr/bin/env bash
# Tests for telegram-send.sh against a local stub of the Telegram Bot API.
# Usage: scripts/telegram-send_test.sh
set -euo pipefail
cd "$(dirname "$0")"

work="$(mktemp -d)"
trap 'kill "$stub_pid" 2>/dev/null || true; rm -rf "$work"' EXIT

# Stub: records each sendMessage text to $work/got-NNNN; returns 400 when chat_id is "bad".
cat > "$work/stub.py" <<'PY'
import http.server, json, os, sys, urllib.parse
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        form = urllib.parse.parse_qs(body, keep_blank_values=True)
        if form["chat_id"][0] == "bad":
            self.send_response(400); self.end_headers()
            self.wfile.write(json.dumps({"ok": False, "description": "Bad Request: chat not found"}).encode())
            return
        n = len([f for f in os.listdir(out) if f.startswith("got-")])
        with open(os.path.join(out, "got-%04d" % n), "w") as f:
            f.write(form["text"][0])
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"ok":true}')
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(out, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$work/stub.py" "$work" & stub_pid=$!
for _ in $(seq 50); do [[ -s "$work/port" ]] && break; sleep 0.1; done

export NO_PROXY="127.0.0.1" no_proxy="127.0.0.1"
export TELEGRAM_API_URL="http://127.0.0.1:$(cat "$work/port")"
export TELEGRAM_BOT_TOKEN="123:SECRET-TOKEN" TELEGRAM_CHAT_ID="42"

fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
reset() { rm -f "$work"/got-*; }
joined() { local first=1; for f in "$work"/got-*; do [[ $first == 1 ]] || printf '\n'; cat "$f"; first=0; done; }

reset; printf 'line one\nline two\n' | ./telegram-send.sh >/dev/null
check "short input is one message" '[[ $(ls "$work"/got-* | wc -l) == 1 && "$(cat "$work"/got-0000)" == $'"'"'line one\nline two'"'"' ]]'

reset; seq 1 400 > "$work/long"; TELEGRAM_MAX_CHARS=100 ./telegram-send.sh < "$work/long" >/dev/null
check "long input splits on lines" '[[ $(ls "$work"/got-* | wc -l) -gt 1 ]]'
longest=0; for f in "$work"/got-*; do n=$(wc -m < "$f"); (( n > longest )) && longest=$n; done
check "every part within limit" '[[ $longest -le 100 ]]'
check "parts rejoin to the input in order" '[[ "$(joined)" == "$(cat "$work/long")" ]]'

reset; head -c 250 /dev/zero | tr "\0" x | TELEGRAM_MAX_CHARS=100 ./telegram-send.sh >/dev/null
check "single long line is hard-split" '[[ $(ls "$work"/got-* | wc -l) == 3 && $(cat "$work"/got-* | wc -c) == 250 ]]'

reset; printf 'é€ unicode\n' | ./telegram-send.sh >/dev/null
check "unicode passes through" '[[ "$(cat "$work"/got-0000)" == "é€ unicode" ]]'

set +e
echo hi | TELEGRAM_BOT_TOKEN= ./telegram-send.sh 2>/dev/null; rc=$?
check "missing token exits 2" '[[ $rc == 2 ]]'
./telegram-send.sh < /dev/null 2>/dev/null; rc=$?
check "empty input exits 2" '[[ $rc == 2 ]]'
err="$(echo hi | TELEGRAM_CHAT_ID=bad ./telegram-send.sh 2>&1 >/dev/null)"; rc=$?
check "rejected message exits 1" '[[ $rc == 1 ]]'
check "error shows Telegram description" '[[ "$err" == *"chat not found"* ]]'
check "error never shows the token" '[[ "$err" != *SECRET-TOKEN* ]]'
err="$(echo hi | TELEGRAM_API_URL=http://127.0.0.1:1 ./telegram-send.sh 2>&1 >/dev/null)"; rc=$?
check "network failure exits 1 without the token" '[[ $rc == 1 && "$err" != *SECRET-TOKEN* ]]'
set -e

[[ $fails == 0 ]] && echo "all tests passed" || { echo "$fails test(s) failed"; exit 1; }
