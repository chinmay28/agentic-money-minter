# Running the trading rules

Two scheduled routines trigger this repository with the same one line: **"Follow all the rules in the repository, one after the other."** When you get that instruction:

1. Run each rule in `rules/` **in this order**, one at a time, to completion before starting the next:
   1. `rules/tqqq-swing.md`
   2. `rules/btc-usdg.md`
2. The rules are independent. "Stop" or "report and stop" inside a rule ends **that rule only**; always go on to the next rule. A rule that does nothing this run (e.g. `OUTSIDE_EQUITY_WINDOW`) still produces its one-line report.
3. Each rule reads the current time itself when it starts. Never reuse a snapshot, quote, order list or cash figure from an earlier rule; each rule rebuilds its own state from the account.
4. Never mix the rules' variables. `ENTRY`, `TARGET_PX`, `FLAT`, `INVALID`, etc. mean the equity sleeve inside `tqqq-swing.md` and the BTC sleeve inside `btc-usdg.md`.
5. Do not edit, commit or push anything in this repository during a run (temporary files go outside it).
6. Finish with each rule's report, in the same order, under a heading per rule.
7. **Send a short summary to Telegram, every run.** The full reports from step 6 stay in the run output; Telegram gets only a human-readable summary — **no JSON, no order IDs, no markdown**. Write it to a temporary file outside the repository, e.g. `f=$(mktemp)`, and run `scripts/telegram-send.sh < "$f"`. Send even when a rule did nothing this run.

   Format — one block per rule, in run order, separated by a blank line; at most ~6 lines per block; times in PT; prices rounded to whole dollars for BTC and cents for stocks; percentages to one decimal:

   ```
   TQQQ · 3:53 PM PT Sat Oct 3
   Market closed (weekend). No orders.

   BTC · 3:53 PM PT Sat Oct 3
   Holding 0.01096 BTC @ $87,261 → target $87,697 (working)
   Bid $84,012 · unrealized −3.7% (−$35.61)
   Bullish: SMA50 $85,071 > SMA200 $84,173
   Sleeve $966.19 · realized P&L −$34.81
   No orders placed or cancelled.
   ```

   - First line of each block: rule name (`TQQQ`, `BTC`) and run time. Then, as applicable: what is held and the working exit; current price and unrealized P&L; regime or entry status (e.g. `Flat · buy resting @ $84,170 (1% below 24h high $85,022)`); sleeve value and realized P&L; and one line listing every fill, placement and cancellation this run, or `No orders placed or cancelled.`
   - Anything flagged (INVALID, VIX_LOW, INVALID_LEDGER, STALE_CANDLES, SPREAD_TOO_WIDE, NO_CHASE_BLOCKED, LONG_UNPROTECTED, a tool failure, …) goes on its own line starting with `⚠️`, as the first line after the header.
   - Sending happens only after both rules have finished. It never changes, delays or retries any trading step.
   - If the script exits non-zero (variables missing, network blocked, Telegram error), do not retry; add one line `TELEGRAM_NOT_SENT: <the script's error message>` at the end of the run output.
   - Never print, echo or log the token, and never put it in a command line you show.

## Schedule assumptions

Each routine schedule runs at most once per hour, so there are **two hourly routines with the same prompt**: one at minute **:18** (cron `18 * * * *`) and one at minute **:48** (cron `48 * * * *`), 24/7. Together they give one run every 30 minutes, which the rules rely on: one run inside each half-hour equity window (`AGGRESSIVE_EXIT`, `FINAL_RUN`), and every run starts after minute :02 so the newest hourly BTC candle has settled. The two runs are 30 minutes apart, so they never overlap; do not schedule either routine on another minute.
