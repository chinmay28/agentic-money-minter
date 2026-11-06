# Running the trading rules

Two scheduled routines trigger this repository with the same one line: **"Follow all the rules in the repository, one after the other."** When you get that instruction:

1. Run each rule in `rules/` **in this order**, one at a time, to completion before starting the next. Today there is one:
   1. `rules/xlk-swing.md`
2. The rules are independent. "Stop" or "report and stop" inside a rule ends **that rule only**; always go on to the next rule. A rule that does nothing this run (e.g. `OUTSIDE_EQUITY_WINDOW`) still produces its one-line report.
3. Each rule reads the current time itself when it starts and rebuilds its own state from the account; never reuse a snapshot, quote, order list or cash figure from an earlier rule.
4. Never mix the rules' variables; a name like `ENTRY` or `TARGET_PX` means what the rule that defines it says, nothing else.
5. Do not edit, commit or push anything in this repository during a run (temporary files go outside it).
6. Finish with each rule's report, in the same order, under a heading per rule.
7. **Append a short entry to the day's Telegram log, every run.** The full reports from step 6 stay in the run output; Telegram gets only a compact human-readable entry — **no JSON, no order IDs, no markdown**. Write it to a temporary file outside the repository, e.g. `f=$(mktemp)`, and run `scripts/telegram-log.sh < "$f"`. Send even when a rule did nothing this run.

   The script keeps **one Telegram message per day** (a day starts at 6:00 AM PT) and appends each run's entry to it under a `── 3:48 PM PT ──` timestamp line it adds itself, so the message reads as the day's timeline. It finds the day's message through the chat's pinned message and starts a new one (or a `(part N)` continuation when Telegram's length limit is reached) on its own. Write only the entry, with no timestamp line or title.

   A day holds up to 48 entries, so keep each one short — one line per rule, in run order, prefixed with the rule name; prices to the cent; percentages to one decimal:

   ```
   XLK: market closed (weekend). No orders.
   XLK: 100 XLK @ $202.90 · bid $167.83 · −17.3% (−$3,507.00; combined −$3,469.00 incl. $38 call premium) · recovery, GTC exit @ $204.55 working · sleeve $17,895.25
     ↳ Bought $5.58 SATA (sweep)
   XLK: flat · ask $164.78 is 18.9% below ATH $203.25 (Oct 2026), no entry · sleeve $17,880.10
   ```

   - The rule's line, as applicable: what is held and the working exit; current price, unrealized and combined P&L; state (`flat`, `open, DAY target @ …`, `recovery, …`), the distance from the all-time high when flat, and any short call; sleeve value (TRADE + PARK + OTHER_PARK + cash) and realized P&L. A rule with nothing to do says so in a few words (`XLK: market closed. No orders.`).
   - Only when a rule had fills, placements or cancellations this run, add one indented line under its line starting with `↳` listing every one of them (e.g. `  ↳ Sold 100 XLK @ $203.41 (+$51) · bought $20,341.00 SATA`). No such line means no orders.
   - Anything flagged (INVALID, ATH_FILTER_BLOCKED, NO_CHASE_BLOCKED, a tool failure, …) goes on its own indented line under the rule's line starting with `⚠️`, before any `↳` line.
   - Sending happens only after all rules have finished. It never changes, delays or retries any trading step.
   - If the script exits non-zero (variables missing, network blocked, Telegram error), do not retry; add one line `TELEGRAM_NOT_SENT: <the script's error message>` at the end of the run output. If it exits 0 but prints a `telegram-log: warning:` line, add `TELEGRAM_WARNING: <that message>` at the end of the run output instead.
   - Never print, echo or log the token, and never put it in a command line you show.

## Schedule assumptions

Each routine schedule runs at most once per hour, so there are **two hourly routines with the same prompt**: one at minute **:18** (cron `18 * * * *`) and one at minute **:48** (cron `48 * * * *`), 24/7. Together they give one run every 30 minutes, which the XLK rule relies on: one run inside each half-hour equity window (`AGGRESSIVE_EXIT`, `FINAL_RUN`). The two runs are 30 minutes apart, so they never overlap; do not schedule either routine on another minute. Runs outside the equity window do nothing but log `market closed`; if you want fewer of them, restrict both routines to weekday US market hours (`18 13-21 * * 1-5` and `48 13-21 * * 1-5`, UTC, which covers 6:30 AM–1:00 PM PT in both PST and PDT) — but keep both minutes.
