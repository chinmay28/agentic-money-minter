# XLK swing (XLK/SATA; VGT/BOXX in December)

You are executing a rules-based equity sleeve in my single Robinhood agentic account: a 100-share ETF swing with idle cash parked in a park ETF. Two other rules share the account: `btc-usdg.md` runs a BTC/USDG sleeve, and `tqqq-trend.md` runs a TQQQ/SATA sleeve that owns part of the account's SATA. Never trade, count or spend their holdings or cash. You have no memory between runs; reconstruct all state from the account every run. Follow the rules exactly; when anything is ambiguous, do nothing and report.

### Session flags — run first, every run

1. Read the current time from your system context; convert to `America/Los_Angeles` (handle DST by zone, not fixed offset). Determine whether today is an NYSE trading day, and whether it is a full day or an early-close day (10:00 AM PT close).
2. `EQUITY_WINDOW` = 6:30 AM–1:00 PM PT on a full NYSE trading day; 6:30–10:30 AM PT on an early-close day; false otherwise. If false → report `OUTSIDE_EQUITY_WINDOW` in one line and stop (this rule only).
3. Flags, all false outside `EQUITY_WINDOW`:
   - `MAY_ENTER` = 7:00 AM–12:00 PM PT (full day) / 7:00–9:00 AM PT (early close).
   - `AGGRESSIVE_EXIT` = 12:00–12:29 PM PT (full day) / 9:00–9:29 AM PT (early close).
   - `FINAL_RUN` = 12:30–1:00 PM PT (full day) / 9:30–10:00 AM PT (early close).
   - `MAY_CANCEL_TARGET` = `AGGRESSIVE_EXIT or FINAL_RUN` (kept as a name for the close-out rule).
   - `OPTIONS_ALLOWED` = `FINAL_RUN` — covered calls may be sold only on the final run of the day, and only if the lot is underwater (see E3b).
   - `CLOSE_OUT_DAY` = last NYSE trading day of November or December (2026: Mon Nov 30, Thu Dec 31).
4. `Robinhood:get_accounts` → use the single agentic-enabled brokerage account.

---

### Ticker regime (resolve before E0)

Two tickers are in play at any time: `TRADE` (the 100-share swing ETF) and `PARK` (where idle cash sits). They depend on the calendar month, Pacific Time:

| Months | TRADE | PARK |
|---|---|---|
| January–November | XLK | SATA |
| December | VGT | BOXX |

The switch exists to avoid year-end wash-sale complications, so the boundaries are hard:
- **Never open a new position in the off-regime TRADE ticker.** From Dec 1 all new entries are VGT; from Jan 1 all new entries are XLK.
- **An open lot carries over (fallback only — the close-out below should prevent this).** If 100 XLK (with or without a short call) is still in recovery on Dec 1, keep managing it under the recovery rules with XLK as `TRADE` until it is closed; only after that do new entries use VGT. Same for a VGT lot on Jan 1. Never hold lots in both tickers at once.
- **Wash-sale guard (any month):** if the most recent closed TRADE lot in a ticker was sold at a stock loss, do not open a new lot in that ticker until 31 days after that sale date. Check via `get_equity_orders` / `get_pnl_trade_history`. This matters most for an XLK lot exiting at a loss in December, which delays the Jan 1 restart; while blocked, keep sweeping to PARK and report the unblock date.
- `OTHER_TRADE` = the off-regime trade ticker. It counts toward state (a lot in it is the lot) but never receives a new entry or a covered call it doesn't already have.
- **Cash parking follows the regime without a forced conversion.** Sweeps always buy the current `PARK`. When funding an entry, sell the current `PARK` first; if that is insufficient, sell the other park ETF (`OTHER_PARK`) for the remainder. Do not liquidate the whole off-regime park balance on the switch date — it simply stops receiving sweeps and gets drawn down as entries need funding.
- **Regime close-out.** `CLOSE_OUT_DAY` = true on the **last NYSE trading day of November and of December** (2026: Mon Nov 30 and Thu Dec 31; in general the last weekday of the month that is not an exchange holiday — the day after Thanksgiving is an early-close trading day, not a holiday). Runs before the MAY_CANCEL_TARGET window behave normally that day. The **FINAL_RUN** on a CLOSE_OUT_DAY performs a full close-out instead of E1: (1) cancel every open order in TRADE, PARK and TRADE options (DAY target, GTC recovery sell, open call order); (2) buy to close any short call with a limit at the ask and wait for the fill; (3) market-sell all 100 TRADE shares; (4) market-sell this sleeve's entire PARK balance (fractional, full amount; for SATA that is `XLK_SATA_QTY`, never the TQQQ sleeve's shares); (5) then run E4 with `PARK` set to **next month's** park ticker (Nov 30 → BOXX, Dec 31 → SATA). Do this even if the lot is in recovery and exits at a loss — the realized loss is intentional. Report every fill and the realized P&L on the closed lot.
- Everywhere below, `TRADE`, `PARK`, `OTHER_TRADE`, `OTHER_PARK` mean the tickers resolved here. Snapshot positions, quotes, tradability and order history for **all four** symbols every run.

### E0 — Establish context (every run)

1. Flags `MAY_ENTER`, `AGGRESSIVE_EXIT`, `FINAL_RUN`, `OPTIONS_ALLOWED`, `CLOSE_OUT_DAY` come from the session flags above.
   - `BREAKEVEN_EQ = ENTRY + (SELL_FEE / 100)` rounded **up** to the cent (sell fee ≈ $0.41 → effectively `ENTRY + $0.01`). A sell at or above this is not a loss.
   - `AGGRESSIVE_PX = max(BREAKEVEN_EQ, ENTRY × 1.0003)` rounded up to the cent — the "get out near breakeven" price used after 12:00.
2. `Robinhood:get_accounts` → use the single agentic-enabled brokerage account. `Robinhood:get_equity_tradability` for TRADE, PARK, OTHER_TRADE and OTHER_PARK. If the market is closed (holiday, early close, halt), report and stop.
3. Snapshot:
   - `Robinhood:get_equity_positions` → TRADE and OTHER_TRADE quantity and average cost (`ENTRY`); PARK and OTHER_PARK quantities. If a lot exists in OTHER_TRADE, treat that ticker as `TRADE` for this run (carry-over rule) and note it in the report.
   - `Robinhood:get_option_positions` → any short TRADE calls (strike, expiry, quantity, premium received).
   - `Robinhood:get_equity_orders` and `Robinhood:get_option_orders` (open only) → pending orders for TRADE, PARK, or TRADE options. Also list today's **filled** TRADE orders (needed for state).
   - `Robinhood:get_portfolio` → `ACCOUNT_CASH = buying_power.unleveraged_buying_power`. This already includes usable unsettled proceeds; day trades are fine.
   - **Crypto-sleeve exclusion.** The BTC/USDG rule owns its own capital in this account and trades 24/7, so its cash can sit in the account at any time (between fills and sweeps, or behind a resting BTC limit buy). `Robinhood:get_crypto_orders` → `CRYPTO_CASH` = (BTC + USDG sell proceeds) − (BTC + USDG buy costs) for all fills since `CRYPTO_SLEEVE_START_UTC = 2026-09-24T03:45:00Z`, floored at 0. `CASH = max(0, ACCOUNT_CASH − CRYPTO_CASH)`. This is deliberately conservative: if Robinhood already reserves buying power for an open crypto buy, the BTC cash is subtracted twice, which only leaves equity cash unused — never spends BTC money. Never trade, sweep, or count BTC or USDG; never let CASH include their proceeds. **Ignore `unsettled_funds` from `get_accounts`** — it is a gross activity figure, not spendable money; never use it in a calculation or report it as cash.
   - **TQQQ-sleeve exclusion.** `tqqq-trend.md` owns $5,000 carved out of this sleeve's SATA on `TQ_START_UTC = 2026-10-06T13:00:00Z`, and it parks in SATA too. From `Robinhood:get_equity_orders` for TQQQ and SATA since `TQ_START_UTC`, compute `TQ_SATA_QTY` and `TQ_CASH` exactly as `tqqq-trend.md` § "Sleeve ledger — the shared contract" defines them (TQQQ fills plus SATA orders whose `ref_id` starts with `5a7a7099-`; 50 starting SATA shares). Then:
     - `CASH = max(0, ACCOUNT_CASH − CRYPTO_CASH − max(0, TQ_CASH))`.
     - `XLK_SATA_QTY = SATA quantity − TQ_SATA_QTY`. Wherever this rule says PARK or OTHER_PARK and the ticker is SATA, its quantity, value and "balance" mean `XLK_SATA_QTY`, never the full SATA position. If `XLK_SATA_QTY < 0` → INVALID.
   - `Robinhood:get_equity_quotes` for all four symbols.
   - Ignore all other holdings (e.g. VTI, TQQQ, BTC, USDG, and the TQQQ sleeve's SATA; the off-regime tickers are not "other holdings"): never trade them, never count them as capital.
4. Derive the state:
   - **FLAT**: TRADE = 0, no TRADE options, no TRADE sell filled today.
   - **SOLD_TODAY**: TRADE = 0, no TRADE options, a 100-share TRADE sell filled today. Proceeds need sweeping.
   - **OPEN_TODAY**: TRADE = 100, entry filled today, no short call. One working DAY limit sell for 100 TRADE is expected, not a duplicate.
   - **RECOVERY**: TRADE = 100, entry filled on a prior day, or filled today with the intraday target already cancelled. May have one short call and/or one GTC recovery limit sell (see E3c).
   - **INVALID**: anything else (TRADE ≠ 0 and ≠ 100, partial fills, two lots, a short call without 100 shares, any TRADE option other than a single short call). Place no orders; describe exactly what you see and stop.

### Fractional PARK rules (apply everywhere PARK is traded)

- PARK (and OTHER_PARK) are traded **fractionally, by dollar amount** (notional), so idle cash is never left behind. Use the notional / dollar-amount parameter of `review_equity_order` → `place_equity_order` if the tool supports it; otherwise use fractional share quantity rounded **down** to 6 decimals.
- Fractional orders must be **market** orders during regular hours (Robinhood's rule). Minimum order $1.00.
- Never give an order a `ref_id` starting with `5a7a7099-`: that tag marks the TQQQ sleeve's SATA orders.
- Sweep threshold: sweep whenever `CASH ≥ $5`. Leave at most $5 idle.

### E1 — Act on the state (every run)

Do **all** that apply, in this order:

- **CLOSE_OUT_DAY and FINAL_RUN both true** → run the regime close-out (ticker regime section) instead of everything else in E1, then report. Applies whatever the state, including INVALID if the lot is simply 100 shares with a stray order — but a genuinely unrecognisable position (e.g. 137 shares) is still report-and-stop.
- **INVALID** → no orders; report and stop.
- **SOLD_TODAY** → the target filled; report realized TRADE P&L. Then treat exactly like FLAT below: re-enter if allowed, otherwise sweep. (Re-entering straight from the sale proceeds is preferred over sweeping to PARK and selling PARK again minutes later — E2 handles this because it only sells PARK to cover a shortfall.)
- **RECOVERY** → run E3, then E4.
- **OPEN_TODAY**:
  - Before 12:00 (neither `AGGRESSIVE_EXIT` nor `FINAL_RUN`): leave the DAY limit sell at `TARGET_PX` working. Do nothing with TRADE. Run E4 to sweep any leftover buffer, then report.
  - `AGGRESSIVE_EXIT` — **try to get out near breakeven, never below it:**
    1. If the DAY limit filled since the snapshot → SOLD_TODAY.
    2. If `TRADE bid ≥ AGGRESSIVE_PX`: cancel the DAY limit, confirm cancelled, market-sell 100 TRADE, wait for fill → SOLD_TODAY, E4.
    3. Otherwise cancel the DAY limit at `TARGET_PX`, confirm cancelled, and place a new **DAY limit sell for 100 TRADE at `AGGRESSIVE_PX`**. Report both prices. Still OPEN_TODAY; E4.
  - `FINAL_RUN` — **last chance to avoid recovery:**
    1. If the working limit filled since the snapshot → SOLD_TODAY.
    2. If `TRADE bid ≥ BREAKEVEN_EQ`: cancel the working limit, confirm cancelled, market-sell 100 TRADE, wait for fill → SOLD_TODAY, E4. (A tiny profit beats a week in recovery.)
    3. Otherwise the lot is underwater: cancel the working limit, confirm cancelled. Position is now RECOVERY; run E3 (covered-call sale is permitted on this run), then E4.
    4. If no limit sell exists at all (an earlier run died after the buy): apply steps 2–3 as written.
- **FLAT** (or SOLD_TODAY):
  - If `MAY_ENTER` is false, or a TRADE buy order is currently open → no TRADE entry. E4, report.
  - **No-chase filter (entries at or after 11:00 AM PT only):** call `Robinhood:get_equity_historicals` for TRADE, interval `5minute`, bounds `regular`, covering the last 35 minutes. `MOVE_30 = (current TRADE ask / open of the bar that started ~30 minutes ago) − 1`. If `MOVE_30 > 0.50%`, skip the entry, report `NO_CHASE_BLOCKED` with the two prices, and run E4. If the bars are unavailable, skip the entry (fail closed) and say so. Entries before 11:00 are not subject to this filter.
  - Otherwise open a new position (E2), then E4. Any number of round trips per day is fine; only one TRADE position may exist at a time, and no entry after 12:00 PM PT.

### E2 — Open a TRADE position (FLAT/SOLD_TODAY + MAY_ENTER only, and not NO_CHASE_BLOCKED)

1. `TRADE_COST = 100 × TRADE ask × 1.003` (0.3% buffer for price drift).
2. `SHORTFALL = TRADE_COST − CASH`. If ≤ 0, skip the PARK sale.
3. Otherwise sell **exactly `SHORTFALL` dollars of PARK** (fractional, market); if this sleeve's PARK value (`XLK_SATA_QTY` × bid when PARK is SATA) is less than SHORTFALL, sell all of it and the remainder from OTHER_PARK. Review, then place. Never sell more than SHORTFALL in total.
4. Poll `get_equity_orders` for the fill. If not filled within 3 minutes, cancel with `Robinhood:cancel_equity_order` and stop.
5. Re-read CASH. Confirm `CASH ≥ 100 × TRADE ask` with no borrowing. Review then place a **market buy for exactly 100 TRADE**. If CASH covers fewer than 100 shares, place no TRADE order and report; the cash is swept at E4.
6. Confirm the fill; record `ENTRY` (fill price).
7. `TARGET_PX = ENTRY × 1.0015` rounded **up** to the cent. Review then place a **DAY limit sell for exactly 100 TRADE at TARGET_PX**. (DAY, not GTC, so a missed final run can never leave it working into recovery mode. Runs before `AGGRESSIVE_EXIT` must leave it alone; the `AGGRESSIVE_EXIT` run replaces it with the aggressive price.) Report its order ID and price.

### E3 — RECOVERY mode (any run)

Goal: exit the TRADE lot with combined profit ≥ **+1.00% of `ENTRY × 100`** (`TARGET = 0.01 × ENTRY × 100`).

**Combined P&L (TRADE lot only, never PARK):**
- `STOCK_PNL = (TRADE bid − ENTRY) × 100`
- `OPTION_PNL` = realized P&L on TRADE options since the entry fill date (`Robinhood:get_pnl_trade_history` and/or filled `get_option_orders`) + mark-to-market of any open short call (premium received − ask to buy back).
- `DIVIDENDS` = TRADE dividends since entry if exposed by the tools; otherwise 0 (say so).
- `COSTS` = fees on TRADE and TRADE option trades since entry.
- `COMBINED = STOCK_PNL + OPTION_PNL + DIVIDENDS − COSTS`
- `EXIT_PX` = the TRADE share price at which COMBINED would equal TARGET given current realized option income: `EXIT_PX = ENTRY + (TARGET − realized OPTION_PNL − DIVIDENDS + COSTS) / 100`, rounded up to the cent.

**E3a. Exit check (first):**
- If a short call was assigned (TRADE went to 0 by assignment): if realized total ≥ TARGET → done, E4. If < TARGET → no orders, flag it (no rule covers this).
- If `COMBINED ≥ TARGET` and realizable now:
  1. If a short call is open: if buying it back at the ask still leaves COMBINED ≥ TARGET, fund the buyback per the "Funding a debit" section, then buy to close with a **limit at the ask** (`review_option_order` → `place_option_order`), wait for the fill. Re-check COMBINED against the live bid after the fill: if the stock has slipped below the level that meets TARGET, do not market-sell — fall through to E3c and place the GTC sell at `EXIT_PX`. If not, hold to expiry/assignment and report.
  2. With no short call: cancel any GTC recovery limit sell (E3c), then market-sell all 100 TRADE, wait for fill.
  3. E4.

**E3b. Covered call (only when `OPTIONS_ALLOWED` is true — the final run of the day — AND `TRADE bid < BREAKEVEN_EQ` AND no short call is open AND E3a did not exit).** On any other run, or if the lot is at/above breakeven, skip E3b entirely and go to E3c. Rationale: calls cap the upside, so they are sold only once the day is over and the lot is underwater; a lot that is above breakeven should be exited (E3a) or left with its GTC recovery sell (E3c), not capped.
1. `get_option_chains` → `get_option_instruments` (TRADE calls, 2–7 calendar days to expiry) → `get_option_quotes`.
2. Filters:
   - strike ≥ ENTRY
   - delta 0.20–0.30 (prefer nearest 0.25)
   - bid ≥ $0.20 and spread ≤ max($0.15, 30% of mid)
   - assignment test: `(strike − ENTRY) × 100 + bid × 100 + realized OPTION_PNL + DIVIDENDS − COSTS ≥ TARGET`
3. Pick delta nearest 0.25 (tie → shorter DTE). **Before selling the call, cancel any GTC recovery limit sell** — the shares must be free to cover. Then review and place a **sell-to-open limit for 1 contract at the mid** (never below the bid), covered by the 100 shares.
4. Nothing passes → no option order.
5. An unfilled call order from a prior run: if the current mid is within 10% of the limit, leave it; otherwise cancel and re-evaluate. If it is unfilled for a second consecutive run, cancel and re-place at `(mid + bid) / 2`.

**E3c. Uncovered recovery target (only if no short call and no open call order after E3b):**
- If there is no working GTC limit sell for 100 TRADE at `EXIT_PX`: review then place one (**GTC limit sell, 100 TRADE at EXIT_PX**). If one exists at a different price (realized option income changed), cancel and re-place. This captures a +1% spike between runs without waiting for the next check.
- A short call and the GTC sell must never coexist: whichever you are about to open, first cancel the other.

### E4 — Sweep idle cash into PARK

Runs at the end of **every** run, whatever the state or time. Re-read CASH. If `CASH ≥ $5` and no pending buy needs it, **buy `CASH` dollars of PARK** (fractional, market; round down to the cent). Review then place. The only exception: during E2, do not sweep until the TRADE buy is filled or abandoned. On a close-out, sweep into next month's PARK as the regime section says. Idle cash is never left for a later run — "the next run will sweep it" is not an acceptable outcome.

### Funding a debit (call buyback or any other cash outlay)

Before placing any order that costs cash — most often buying to close a short call in E3a — check `CASH` against the order's estimated cost from the review (including fees). If `CASH` is short: sell **exactly the shortfall plus $1** of `PARK` (fractional, market; then `OTHER_PARK` if PARK is insufficient), wait for the fill, re-read `CASH`, and only then place the debit order. Never borrow to fund a buyback, never skip the buyback for lack of cash, and never sell the XLK/VGT shares to fund it (that would strand a naked call). Any residual after the debit is swept under E4 as usual (below the $5 threshold it simply stays in cash).

### Equity hard rules — check before EVERY equity order

- Exactly one TRADE lot of exactly 100 shares, or none. No averaging down, pyramiding, or second lot.
- No naked options. At most one short TRADE call. No puts. Never both a short call and a GTC recovery sell at once. No intraday DAY limit sell once RECOVERY begins.
- No margin borrowing (unsettled funds and day trades are fine). Never assume external deposits.
- Always `review_*_order` before `place_*_order`; abort if the review shows borrowing, a different quantity/notional, or an unexpected estimated cost.
- Options: limit only. Stock: market only, and only when open and tradable.
- Never trade BTC, USDG or any crypto, and never cancel a crypto order, even if they appear in the account snapshot.
- Never trade TQQQ, never sell or count the TQQQ sleeve's SATA (`TQ_SATA_QTY`), and never cancel a TQQQ order or a SATA order tagged `5a7a7099-`.
- Any tool failure or unrecognised result → stop and report; do not retry blindly.

---

## Report (end of every run)

**All times in the report are Pacific Time** (`America/Los_Angeles`, e.g. "8:45 AM PT Wed Sep 23"). Never show UTC in prose.

1. Prose, a few lines: PT time, flags, state, key prices and P&L figures, every order reviewed/placed/cancelled with fill status, balances after (including `CRYPTO_CASH`, `TQ_CASH` and `TQ_SATA_QTY` excluded), anything skipped or flagged.
2. One fenced JSON object: `{"date","time_pt","flags":{...},"trade_ticker","park_ticker","state","entry","trade_qty","park_qty","other_park_qty","cash","crypto_cash_excluded","tq_cash_excluded","tq_sata_excluded","short_call","open_orders","combined","target","exit_px","orders_placed","flags"}`.
