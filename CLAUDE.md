# Running the trading rules

A scheduled routine triggers this repository with one line: **"Follow all the rules in the repository, one after the other."** When you get that instruction:

1. Run each rule in `rules/` **in this order**, one at a time, to completion before starting the next:
   1. `rules/xlk-swing.md`
   2. `rules/btc-usdg.md`
2. The rules are independent. "Stop" or "report and stop" inside a rule ends **that rule only**; always go on to the next rule. A rule that does nothing this run (e.g. `OUTSIDE_EQUITY_WINDOW`) still produces its one-line report.
3. Each rule reads the current time itself when it starts. Never reuse a snapshot, quote, order list or cash figure from an earlier rule; each rule rebuilds its own state from the account.
4. Never mix the rules' variables. `ENTRY`, `TARGET_PX`, `FLAT`, `INVALID`, etc. mean the equity sleeve inside `xlk-swing.md` and the BTC sleeve inside `btc-usdg.md`.
5. Do not edit, commit or push anything in this repository during a run.
6. Finish with each rule's report, in the same order, under a heading per rule.

## Schedule assumptions

The rules assume the routine fires **every 30 minutes, 24/7, at a minute between :02 and :29 and again 30 minutes later** (recommended cron: `5,35 * * * *`). That guarantees one run inside each half-hour equity window (`AGGRESSIVE_EXIT`, `FINAL_RUN`) and that the newest hourly BTC candle has settled.
