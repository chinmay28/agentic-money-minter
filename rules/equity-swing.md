# Equity swing (TQQQ or XLK, trend-gated; idle cash in SATA)

You are executing a rules-based equity sleeve in my single Robinhood agentic account: a 100-share ETF swing with idle cash parked in a park ETF. A separate rule (`btc-usdg.md`) runs a BTC/USDG sleeve in the same account; never trade, count or spend its holdings or cash. You have no memory between runs; reconstruct all state from the account every run. Follow the rules exactly; when anything is ambiguous, do nothing and report.

### Session flags — run first, every run

1. Read the current time from your system context; convert to `America/Los_Angeles` (handle DST by zone, not fixed offset). Determine whether today is an NYSE trading day, and whether it is a full day or an early-close day (10:00 AM PT close).
2. `EQUITY_WINDOW` = 6:30 AM–1:00 PM PT on a full NYSE trading day; 6:30–10:30 AM PT on an early-close day; false otherwise. If false → report `OUTSIDE_EQUITY_WINDOW` in one line and stop (this rule only).
3. Flags, all false outside `EQUITY_WINDOW`:
   - `MAY_ENTER` = 7:00 AM–12:00 PM PT (full day) / 7:00–9:00 AM PT (early close).
   - `AGGRESSIVE_EXIT` = 12:00–12:29 PM PT (full day) / 9:00–9:29 AM PT (early close).
   - `FINAL_RUN` = 12:30–1:00 PM PT (full day) / 9:30–10:00 AM PT (early close).
   - `OPTIONS_ALLOWED` = `FINAL_RUN` — covered calls may be sold only on the final run of the day, and only if the lot is underwater (see E3b).
4. `Robinhood:get_accounts` → use the single agentic-enabled brokerage account.

---

### Tickers and the trend gate

`PARK` = **SATA** (where idle cash sits), all year. The 100-share swing ticker `TRADE` is either **TQQQ** or **XLK**:

- **Open lot → its ticker.** If the account holds a lot in TQQQ or XLK (with or without a short call), `TRADE` is that ticker, whatever the gate says today. The lot is managed under E1/E3 until it is closed; it is never switched, sold or added to because the gate changed. Holding shares in both TQQQ and XLK at once is INVALID.
- **No open lot → the gate picks the next entry.** Computed only when the state is FLAT/SOLD_TODAY and `MAY_ENTER` is true (otherwise report it as not checked):
  - `QQQ_TREND_OK` = QQQ's current price is **strictly above** its 200-day simple moving average. `SMA200_QQQ` = mean of the last 200 **completed** daily closes (exclude today's session): `Robinhood:get_equity_historicals` for QQQ, interval `day`, span long enough to cover 200 sessions (e.g. `year`), bounds `regular`. Current price = QQQ last trade from `Robinhood:get_equity_quotes`. Fewer than 200 completed closes, a gap in the series, or a newest close older than the previous NYSE trading day → `QQQ_TREND_OK` = false and say so.
  - `VIX_OK` = the latest VIX index level is **strictly above 16.00**. Read it with `Robinhood:get_index_quotes` for `VIX` (use `Robinhood:get_indexes` / `Robinhood:search` to resolve the symbol if needed). Unavailable, stale (older than 15 minutes) or unrecognised → `VIX_OK` = false and say so.
  - `TQQQ_GATE = QQQ_TREND_OK and VIX_OK`. If true → `TRADE` = **TQQQ**; otherwise → `TRADE` = **XLK**. Any gate data failure therefore falls back to XLK (fail safe, never to TQQQ). The gate only chooses the ticker; it never blocks an entry on its own.
- Everywhere below, `TRADE` and `PARK` mean the tickers resolved here. Snapshot positions, quotes, tradability and order history for TQQQ, XLK and SATA every run.
- **Legacy park balances.** Any VGT or BOXX left from the old December regime is ignored like any other holding: never traded, never counted as capital.

---

### E0 — Establish context (every run)

1. Flags `MAY_ENTER`, `AGGRESSIVE_EXIT`, `FINAL_RUN`, `OPTIONS_ALLOWED` come from the session flags above.
   - `BREAKEVEN_EQ = ENTRY + (SELL_FEE / 100)` rounded **up** to the cent (sell fee ≈ $0.41 → effectively `ENTRY + $0.01`). A sell at or above this is not a loss.
   - `AGGRESSIVE_PX = max(BREAKEVEN_EQ, ENTRY × 1.0003)` rounded up to the cent — the "get out near breakeven" price used after 12:00.
2. `Robinhood:get_accounts` → use the single agentic-enabled brokerage account. `Robinhood:get_equity_tradability` for TQQQ, XLK and SATA. If the market is closed (holiday, early close, halt), report and stop.
3. Snapshot:
   - `Robinhood:get_equity_positions` → TQQQ and XLK quantity and average cost (`ENTRY` of whichever is held); PARK quantity. Resolve `TRADE` per the section above.
   - `Robinhood:get_option_positions` → any short TRADE calls (strike, expiry, quantity, premium received).
   - `Robinhood:get_equity_orders` and `Robinhood:get_option_orders` (open only) → pending orders for TRADE, PARK, or TRADE options. Also list today's **filled** TQQQ and XLK orders (needed for state: a sell filled today in either ticker counts for SOLD_TODAY).
   - `Robinhood:get_portfolio` → `ACCOUNT_CASH = buying_power.unleveraged_buying_power`. This already includes usable unsettled proceeds; day trades are fine.
   - **Crypto-sleeve exclusion.** The BTC/USDG rule owns its own capital in this account and trades 24/7, so its cash can sit in the account at any time (between fills and sweeps, or behind a resting BTC limit buy). `Robinhood:get_crypto_orders` → `CRYPTO_CASH` = (BTC + USDG sell proceeds) − (BTC + USDG buy costs) for all fills since `CRYPTO_SLEEVE_START_UTC = 2026-09-24T03:45:00Z`, floored at 0. `CASH = max(0, ACCOUNT_CASH − CRYPTO_CASH)`. This is deliberately conservative: if Robinhood already reserves buying power for an open crypto buy, the BTC cash is subtracted twice, which only leaves equity cash unused — never spends BTC money. Never trade, sweep, or count BTC or USDG; never let CASH include their proceeds. **Ignore `unsettled_funds` from `get_accounts`** — it is a gross activity figure, not spendable money; never use it in a calculation or report it as cash.
   - `Robinhood:get_equity_quotes` for TQQQ, XLK, SATA and QQQ.
   - Ignore all other holdings (e.g. VTI, BTC, USDG, VGT, BOXX, QQQ): never trade them, never count them as capital.
4. Derive the state:
   - **FLAT**: TQQQ = 0 and XLK = 0, no TQQQ/XLK options, no TQQQ/XLK sell filled today.
   - **SOLD_TODAY**: TQQQ = 0 and XLK = 0, no TQQQ/XLK options, a 100-share TQQQ or XLK sell filled today. Proceeds need sweeping.
   - **OPEN_TODAY**: TRADE = 100, entry filled today, no short call. One working DAY limit sell for 100 TRADE is expected, not a duplicate.
   - **RECOVERY**: TRADE = 100, entry filled on a prior day, or filled today with the intraday target already cancelled. May have one short call and/or one GTC recovery limit sell (see E3c).
   - **INVALID**: anything else (TRADE ≠ 0 and ≠ 100, partial fills, two lots, shares in both TQQQ and XLK, a short call without 100 shares, any TRADE option other than a single short call). Place no orders; describe exactly what you see and stop.

### Fractional PARK rules (apply everywhere PARK is traded)

- PARK is traded **fractionally, by dollar amount** (notional), so idle cash is never left behind. Use the notional / dollar-amount parameter of `review_equity_order` → `place_equity_order` if the tool supports it; otherwise use fractional share quantity rounded **down** to 6 decimals.
- Fractional orders must be **market** orders during regular hours (Robinhood's rule). Minimum order $1.00.
- Sweep threshold: sweep whenever `CASH ≥ $5`. Leave at most $5 idle.

### E1 — Act on the state (every run)

Do **all** that apply, in this order:

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
  - If `MAY_ENTER` is false, or a TQQQ or XLK buy order is currently open → no entry. E4, report.
  - Resolve the trend gate (Tickers section) to choose `TRADE` = TQQQ or XLK, and report QQQ, `SMA200_QQQ`, VIX and the choice.
  - **No-chase filter (entries at or after 11:00 AM PT only):** call `Robinhood:get_equity_historicals` for TRADE, interval `5minute`, bounds `regular`, covering the last 35 minutes. `MOVE_30 = (current TRADE ask / open of the bar that started ~30 minutes ago) − 1`. If `MOVE_30 > 0.50%`, skip the entry, report `NO_CHASE_BLOCKED` with the two prices, and run E4. If the bars are unavailable, skip the entry (fail closed) and say so. Entries before 11:00 are not subject to this filter.
  - Otherwise open a new position (E2), then E4. Any number of round trips per day is fine; only one TRADE position may exist at a time, and no entry after 12:00 PM PT.

### E2 — Open a TRADE position (FLAT/SOLD_TODAY + MAY_ENTER only, and not NO_CHASE_BLOCKED; TRADE as chosen by the trend gate)

1. `TRADE_COST = 100 × TRADE ask × 1.003` (0.3% buffer for price drift).
2. `SHORTFALL = TRADE_COST − CASH`. If ≤ 0, skip the PARK sale.
3. Otherwise sell **exactly `SHORTFALL` dollars of PARK** (fractional, market); if PARK's value is less than SHORTFALL, sell all of it. Review, then place. Never sell more than SHORTFALL in total.
4. Poll `get_equity_orders` for the fill. If not filled within 3 minutes, cancel with `Robinhood:cancel_equity_order` and stop.
5. Re-read CASH. Confirm `CASH ≥ 100 × TRADE ask` with no borrowing. Review then place a **market buy for exactly 100 TRADE**. If CASH covers fewer than 100 shares, place no TRADE order and report; the cash is swept at E4.
6. Confirm the fill; record `ENTRY` (fill price).
7. `TARGET_PX = ENTRY × 1.0070` (+0.70%, same for TQQQ and XLK) rounded **up** to the cent. Review then place a **DAY limit sell for exactly 100 TRADE at TARGET_PX**. (DAY, not GTC, so a missed final run can never leave it working into recovery mode. Runs before `AGGRESSIVE_EXIT` must leave it alone; the `AGGRESSIVE_EXIT` run replaces it with the aggressive price.) Report its order ID and price.

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

Runs at the end of **every** run, whatever the state or time. Re-read CASH. If `CASH ≥ $5` and no pending buy needs it, **buy `CASH` dollars of PARK** (fractional, market; round down to the cent). Review then place. The only exception: during E2, do not sweep until the TRADE buy is filled or abandoned. Idle cash is never left for a later run — "the next run will sweep it" is not an acceptable outcome.

### Funding a debit (call buyback or any other cash outlay)

Before placing any order that costs cash — most often buying to close a short call in E3a — check `CASH` against the order's estimated cost from the review (including fees). If `CASH` is short: sell **exactly the shortfall plus $1** of `PARK` (fractional, market), wait for the fill, re-read `CASH`, and only then place the debit order. Never borrow to fund a buyback, never skip the buyback for lack of cash, and never sell the TRADE shares to fund it (that would strand a naked call). Any residual after the debit is swept under E4 as usual (below the $5 threshold it simply stays in cash).

### Equity hard rules — check before EVERY equity order

- Exactly one TRADE lot of exactly 100 shares, or none. No averaging down, pyramiding, or second lot.
- No naked options. At most one short TRADE call. No puts. Never both a short call and a GTC recovery sell at once. No intraday DAY limit sell once RECOVERY begins.
- No margin borrowing (unsettled funds and day trades are fine). Never assume external deposits.
- Always `review_*_order` before `place_*_order`; abort if the review shows borrowing, a different quantity/notional, or an unexpected estimated cost.
- Options: limit only. Stock: market only, and only when open and tradable.
- Never trade BTC, USDG or any crypto, and never cancel a crypto order, even if they appear in the account snapshot.
- Any tool failure or unrecognised result → stop and report; do not retry blindly.

---

## Report (end of every run)

**All times in the report are Pacific Time** (`America/Los_Angeles`, e.g. "8:45 AM PT Wed Sep 23"). Never show UTC in prose.

1. Prose, a few lines: PT time, flags, trend gate (QQQ vs `SMA200_QQQ`, VIX, `TQQQ_GATE`, or not checked), `TRADE` ticker, state, key prices and P&L figures, every order reviewed/placed/cancelled with fill status, balances after (including `CRYPTO_CASH` excluded), anything skipped or flagged.
2. One fenced JSON object: `{"date","time_pt","gate":{"qqq","qqq_sma200","vix","tqqq_gate"},"flags":{...},"trade_ticker","park_ticker","state","entry","trade_qty","park_qty","cash","crypto_cash_excluded","short_call","open_orders","combined","target","exit_px","orders_placed","flags"}`.
