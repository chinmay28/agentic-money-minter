# TQQQ trend (TQQQ, or GLD + SATA, on QQQ's 200-day average)

You are executing a rules-based trend sleeve in my single Robinhood agentic account: hold TQQQ while QQQ closes above its 200-day simple moving average, and hold half GLD, half SATA after QQQ closes at or below it. GLD is never sold at a loss. Two other rules share the account: `xlk-swing.md` (XLK/VGT, SATA/BOXX and XLK/VGT options) and `btc-usdg.md` (BTC/USDG). **SATA is shared with `xlk-swing.md`**: this sleeve owns only the SATA shares its ledger below assigns to it. Never trade, count or spend the other sleeves' holdings or cash. You have no memory between runs; reconstruct all state from the account every run. Follow the rules exactly; when anything is ambiguous, do nothing and report.

### Configuration

- `SIGNAL = QQQ` (never traded), `RISK_ON = TQQQ`, `RISK_OFF = 50% GLD + 50% SATA` (by value, set when the sleeve switches into risk-off)
- `GLD_MIN_GAIN = 0.10%` — GLD is sold only when its bid is at least `GLD average cost × 1.001` (`GLD_SELL_OK`), so a market sell cannot realize a loss after slippage and fees
- `START_CAPITAL = $5,000.00`, carved out of the XLK sleeve's SATA as `START_SATA_QTY = 50.000000` SATA shares (~$100 each)
- `TQ_START_UTC = 2026-10-06T13:00:00Z` (6:00 AM PT Tue Oct 6, before the open). At this instant the sleeve held 50.000000 SATA, 0 TQQQ, 0 GLD and $0.00 cash (the account held no TQQQ or GLD).
- `SMA_LEN = 200` completed daily closes of QQQ (regular session, split-adjusted)
- `TAG = 5a7a7099` — the first 8 hex characters of the `ref_id` of **every** order this rule places (see "Order tagging")
- Fractional shares, market orders, regular hours only. No limit orders, no options, no margin.

### Sleeve ledger — the shared contract

`xlk-swing.md` computes the same two numbers to exclude this sleeve from its own cash and SATA, so define them exactly like this and nothing else:

- **Sleeve orders** = filled (or partially filled) equity orders created at or after `TQ_START_UTC` that are either (a) any **TQQQ** or **GLD** order, whatever its `ref_id` (all TQQQ and GLD belong to this sleeve, including trades I place by hand), or (b) a **SATA** order whose `ref_id` starts with `5a7a7099-` (case-insensitive). Use executed quantity, `average_price` and `fees`, never the submitted amount. SATA orders without the tag belong to `xlk-swing.md`, including SATA trades I place by hand.
- `TQ_SATA_QTY = 50.000000 + Σ tagged SATA buy quantity − Σ tagged SATA sell quantity`
- `TQ_CASH = Σ sleeve sell proceeds − Σ sleeve buy costs − Σ sleeve fees` (proceeds/costs = executed quantity × `average_price`), rounded to the cent. The starting SATA is an asset, not cash, so `TQ_CASH` starts at $0.00. `xlk-swing.md` subtracts `max(0, TQ_CASH)`.
- Dividends paid on TQQQ or on the sleeve's SATA (GLD pays none) are **not** attributed to this sleeve — the tools do not identify them per share. They land in account cash and `xlk-swing.md` sweeps them. Report this as a known leak, not an error.

### Order tagging

Every order this rule places uses a fresh `ref_id` whose first group is `5a7a7099`: generate a random UUID v4 (e.g. `python3 -c 'import uuid;print(uuid.uuid4())'`) and replace its first 8 hex characters with `5a7a7099`. Use a new one per logical order and resend the same one only on a transport-level retry of that same order. An order placed without the tag cannot be attributed — if it happens, report `UNTAGGED_ORDER` with its ID. Never use the tag for anything else.

### T0 — Session flags (every run)

1. Read the current time from your system context; convert to `America/Los_Angeles` (handle DST by zone, not fixed offset). Determine whether today is an NYSE trading day and whether it is a full day or an early-close day (10:00 AM PT close).
2. `TQ_WINDOW` = 6:45 AM–12:50 PM PT on a full NYSE trading day; 6:45–9:50 AM PT on an early-close day; false otherwise. The first 15 minutes after the open and the last 10 before the close are skipped on purpose. If false → report `OUTSIDE_TQ_WINDOW` in one line and stop (this rule only).
3. `Robinhood:get_accounts` → use the single agentic-enabled brokerage account. `Robinhood:get_equity_tradability` for TQQQ, GLD, SATA and QQQ. If TQQQ, GLD or SATA is not tradable in regular hours, or fractional trading is unavailable for any of them, report and stop.

### T1 — Signal

1. `Robinhood:get_equity_historicals` for QQQ, `interval = day`, `bounds = regular`, `adjustment_type = split`, `start_time` = 320 calendar days ago (UTC). Bars are labelled by session date (`begins_at` = `YYYY-MM-DDT00:00:00Z`).
2. Drop today's bar (its `close_price` is the live price, not a close) and any bar with `interpolated = true`. Sort chronologically.
3. **Freshness:** the newest remaining bar must be the previous NYSE trading day. Require at least 200 bars. Otherwise → `STALE_DAILY_BARS`: no selling and no buying this run; report.
4. `CLOSE = ` the newest bar's `close_price`; `SMA200` = arithmetic mean of the 200 newest `close_price`s (including `CLOSE`).
5. `SIGNAL = RISK_ON` if `CLOSE > SMA200`, else `RISK_OFF`.
6. The signal is based only on completed closes and is acted on during the next session. A cross at today's close is traded tomorrow at the first run in `TQ_WINDOW`. Never use an intraday QQQ price to decide.

### T2 — Snapshot and state (every run)

1. `Robinhood:get_equity_positions` → TQQQ and GLD quantity, `shares_available_for_sells`, `average_buy_price`; SATA quantity and `shares_available_for_sells`. `GLD_COST = GLD average_buy_price`.
2. `Robinhood:get_equity_orders` for TQQQ, GLD and SATA with `created_at_gte = TQ_START_UTC` (page until `next` is empty). From these build the ledger above. Also list open (non-terminal) TQQQ and GLD orders and open tagged SATA orders.
3. `Robinhood:get_portfolio` → `ACCOUNT_CASH = buying_power.unleveraged_buying_power`. `CRYPTO_CASH` exactly as defined in `xlk-swing.md` E0. `FREE_CASH = ACCOUNT_CASH − CRYPTO_CASH`.
4. `Robinhood:get_equity_quotes` for TQQQ, GLD, SATA and QQQ. `GLD_SELL_OK = GLD bid ≥ GLD_COST × 1.001`.
5. Reconcile, else **INVALID_LEDGER** (no orders; describe the mismatch and stop):
   - TQQQ and GLD position quantities each = Σ buy fills − Σ sell fills since `TQ_START_UTC` (±0.000002).
   - `0 ≤ TQ_SATA_QTY ≤ SATA position quantity`.
   - `TQ_CASH ≥ −$1.00`.
6. Classify (GLD may be present in either regime — see T3):
   - `ORDER_PENDING`: an open TQQQ or GLD order or an open tagged SATA order exists. Market orders normally fill instantly; poll it for up to 3 minutes. If it reaches a terminal state, refresh T2 and continue. Otherwise cancel it with `Robinhood:cancel_equity_order`, confirm it is terminal, report and stop.
   - `RISK_ON_HELD`: TQQQ > 0, `TQ_SATA_QTY = 0`; GLD may be > 0 only as an underwater carry (`GLD_CARRY`).
   - `RISK_OFF_HELD`: TQQQ = 0 and (`TQ_SATA_QTY > 0` or GLD > 0).
   - `CASH_ONLY`: TQQQ = 0, `TQ_SATA_QTY = 0`, GLD = 0, `TQ_CASH ≥ $1` (a previous run died between the sell and the buy).
   - `INVALID`: anything else, e.g. TQQQ > 0 and `TQ_SATA_QTY > 0` at the same time (should only exist mid-switch) or a short position. No orders; report and stop.

### T3 — Act (only inside `TQ_WINDOW`, and not when `STALE_DAILY_BARS`)

Do the steps in order. Each is idempotent: if the holdings already match, the step does nothing.

1. **Sell what the signal no longer wants.**
   - `SIGNAL = RISK_OFF`: if TQQQ > 0 → market-sell **all** TQQQ by quantity (the full position, fractional to 6 decimals). Never sell GLD or SATA in risk-off.
   - `SIGNAL = RISK_ON`:
     - if `TQ_SATA_QTY > 0` → market-sell exactly `TQ_SATA_QTY` SATA by quantity. Never sell more SATA than `TQ_SATA_QTY`: the rest belongs to the XLK sleeve.
     - if GLD > 0 and `GLD_SELL_OK` → market-sell **all** GLD by quantity.
     - if GLD > 0 and not `GLD_SELL_OK` → **do not sell GLD.** It stays as `GLD_CARRY`; report `GLD_HELD_UNDERWATER` with GLD cost, bid and unrealized P&L. Every later run in risk-on checks again and sells it as soon as `GLD_SELL_OK`; its proceeds then go into TQQQ.
   - Wait for each fill.
2. Re-read positions, the orders since `TQ_START_UTC` and `ACCOUNT_CASH`; rebuild `TQ_CASH` from the actual fills.
3. **Deploy sleeve cash** if `TQ_CASH ≥ $5.00`. Before any buy require `TQ_CASH ≤ FREE_CASH + $1.00`; if not, the other sleeves have spent this sleeve's cash → report `CASH_SHORTFALL` with both numbers and place no buy.
   - `SIGNAL = RISK_ON` → market-buy TQQQ for `TQ_CASH` rounded **down** to the cent.
   - `SIGNAL = RISK_OFF` → split so the sleeve is half GLD, half SATA by value:
     - `SLEEVE_VALUE = GLD qty × GLD bid + TQ_SATA_QTY × SATA bid + TQ_CASH`.
     - `GLD_BUY = min(TQ_CASH, max(0, SLEEVE_VALUE / 2 − GLD qty × GLD bid))`, rounded down to the cent. A `GLD_CARRY` from an earlier cycle counts toward the GLD half, so less (or no) new GLD is bought.
     - `SATA_BUY = TQ_CASH − GLD_BUY`, rounded down to the cent.
     - Market-buy GLD for `GLD_BUY`, then SATA for `SATA_BUY`; skip either leg below $1.00.
   - Below $5.00 the residue stays as sleeve cash (excluded from the XLK sweep) and is deployed with the next switch.
4. Confirm every fill from order status and positions; never infer it from price.

The 50/50 split is set only when cash is deployed. While risk-off, GLD and SATA are left to drift — never rebalanced by selling. The sleeve ends a run fully invested for its signal (plus < $5 of cash and any `GLD_CARRY`), or in a reported intermediate state that the next run completes from the ledger.

### Order protocol — before EVERY order

- `Robinhood:review_equity_order` then `Robinhood:place_equity_order` with the identical payload plus the tagged `ref_id`. `type = market`, `market_hours = regular_hours`, `time_in_force = gfd`.
- Sells by `quantity`; buys by `dollar_amount`. Minimum $1.00.
- Abort that order and report if the review shows margin or borrowing, a different symbol, side, quantity or amount, a halt, or an estimated cost above `TQ_CASH`.
- Poll `get_equity_orders` by `order_id` until filled (up to 3 minutes). Partial fill → cancel the remainder, confirm it is terminal, rebuild the ledger and continue from actual fills. Never place a duplicate order because an earlier one looks slow.

### Hard rules

- The only symbols this rule trades are TQQQ, GLD and the sleeve's own SATA (`TQ_SATA_QTY`). QQQ is read-only.
- **Never sell GLD at a loss**: a GLD sell is placed only when `GLD_SELL_OK` is true on a fresh quote taken just before the review, and only in risk-on. No stop, regime, cash need or rebalance overrides this.
- Never hold TQQQ and the sleeve's SATA at the same time beyond a single switch; never buy TQQQ while `SIGNAL = RISK_OFF`; never buy GLD or SATA while `SIGNAL = RISK_ON`.
- No leverage beyond TQQQ itself: no margin, no options, no short sales, no limit or stop orders.
- Never use XLK-sleeve cash or SATA, or BTC/USDG cash. Never touch XLK, VGT, BOXX, XLK/VGT options, BTC, USDG or any crypto order, even if they appear in the snapshot.
- Never switch on an intraday QQQ price, on stale or incomplete daily bars, or outside `TQ_WINDOW`.
- Any tool failure, unrecognised result or non-terminal cancellation → stop and report. Do not retry blindly.

---

## Report (end of every run)

**All times in the report are Pacific Time** (`America/Los_Angeles`). Never show UTC in prose.

1. Prose, a few lines: PT time; QQQ `CLOSE` (with its date), `SMA200`, the gap in %, and the signal; state; TQQQ quantity, average cost, bid and unrealized P&L; GLD quantity, `GLD_COST`, bid, unrealized P&L and whether it is a `GLD_CARRY`; `TQ_SATA_QTY` and SATA bid; `TQ_CASH`; sleeve value `= TQQQ qty × TQQQ bid + GLD qty × GLD bid + TQ_SATA_QTY × SATA bid + TQ_CASH` and its return against `START_CAPITAL`; every order reviewed/placed/cancelled with fill status; anything skipped or flagged.
2. One fenced JSON object: `{"date","time_pt","signal","qqq_close","qqq_close_date","sma200","state","tqqq_qty","tqqq_avg_cost","tqqq_bid","gld_qty","gld_cost","gld_bid","gld_carry","tq_sata_qty","sata_bid","tq_cash","sleeve_value","return_vs_start","orders_placed","fills","flags"}`.
