# Running the trading rules

Two scheduled routines trigger this repository with the same one line: **"Follow all the rules in the repository, one after the other."** When you get that instruction:

1. Run each rule in `rules/` **in this order**, one at a time, to completion before starting the next:
   1. `rules/xlk-swing.md`
   2. `rules/btc-usdg.md`
2. The rules are independent. "Stop" or "report and stop" inside a rule ends **that rule only**; always go on to the next rule. A rule that does nothing this run (e.g. `OUTSIDE_EQUITY_WINDOW`) still produces its one-line report.
3. Each rule reads the current time itself when it starts. Never reuse a snapshot, quote, order list or cash figure from an earlier rule; each rule rebuilds its own state from the account.
4. Never mix the rules' variables. `ENTRY`, `TARGET_PX`, `FLAT`, `INVALID`, etc. mean the equity sleeve inside `xlk-swing.md` and the BTC sleeve inside `btc-usdg.md`.
5. Do not edit, commit or push anything in this repository during a run (temporary files go outside it).
6. Finish with each rule's report, in the same order, under a heading per rule.
7. **Send the reports to Telegram, every run.** Write the complete output from step 6 (both headings, prose and JSON) to a temporary file outside the repository, e.g. `f=$(mktemp)`, and run `scripts/telegram-send.sh < "$f"`. Send even when a rule did nothing this run. The script reads `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` from the environment and splits long reports into several messages.
   - Sending happens only after both rules have finished. It never changes, delays or retries any trading step.
   - If the script exits non-zero (variables missing, network blocked, Telegram error), do not retry; add one line `TELEGRAM_NOT_SENT: <the script's error message>` at the end of the output.
   - Never print, echo or log the token, and never put it in a command line you show.

## Schedule assumptions

Each routine schedule runs at most once per hour, so there are **two hourly routines with the same prompt**: one at minute **:18** (cron `18 * * * *`) and one at minute **:48** (cron `48 * * * *`), 24/7. Together they give one run every 30 minutes, which the rules rely on: one run inside each half-hour equity window (`AGGRESSIVE_EXIT`, `FINAL_RUN`), and every run starts after minute :02 so the newest hourly BTC candle has settled. The two runs are 30 minutes apart, so they never overlap; do not schedule either routine on another minute.
