# BTC/USDG trend sleeve (24/7)

You are executing a rules-based Bitcoin sleeve with cash parked in USDG in my single Robinhood agentic account. A separate rule (`tqqq-swing.md`) runs an equity sleeve (TQQQ/VGT, SATA/BOXX, a legacy XLK lot if any, and their options) in the same account; never trade, count or spend its holdings or cash. You have no memory between runs; reconstruct all state from the account every run. Follow the rules exactly; when anything is ambiguous, do nothing and report.

### Configuration

- `ASSET = BTC`
- `PARK_ASSET = USDG`
- `START_CAPITAL = $1,001.00` (the USDG held at activation)
- `STRATEGY_START_UTC = 2026-09-24T03:45:00Z` (activated; the account held 1,001 USDG and no open crypto orders at this instant)
- **Sleeve scope: all BTC and all USDG in the account belong to this sleeve**, however and whenever acquired. There is no excluded quantity.
- `PULLBACK = 1.00%` — entries rest 1% below the rolling 24-hour high (see B5)
- `HIGH_LOOKBACK = 24 completed hourly candles`
- `PROFIT_TARGET = 0.50%`
- `FAST_MA = 50 completed hourly closes`
- `SLOW_MA = 200 completed hourly closes`
- `ROUTING = market-maker routing with no explicit transaction fee`
- `FEE_RATE = 0` (no explicit fee under market-maker routing; an order review that shows one is aborted per B6)
- `ENTRY_TIF = GTC` (one resting limit buy, repriced when `ENTRY_LIMIT` changes)
- `TARGET_TIF = GTC`
- `BEAR_EXIT_TIF = GTC, repriced each run while bid ≥ breakeven; withdrawn if bid falls below breakeven`
- `NO_LOSS_EXITS = true` — the routine never sells BTC below breakeven, in any regime
- `CANDLE_SOURCE = https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=3600&start=<ISO UTC, now − 220 h>&end=<ISO UTC, now>` — keyless public endpoint, returns up to 300 candles as `[time, low, high, open, close, volume]`, newest first, `time` = Unix epoch of the bucket start. Always pass fresh `start`/`end` so the URL differs every run and no cached copy is served.
- `CANDLE_FALLBACK = https://api.kraken.com/0/public/OHLC?pair=XBTUSD&interval=60` — use only if the Coinbase fetch fails or is stale; never mix the two sources within one run.
- `MAX_SPREAD = 2.00%` — Robinhood BTC (ask − bid) / mid above this blocks new entries (`SPREAD_TOO_WIDE`). Rationale: the +0.5% target fills on the bid, so the spread is a direct cost of every round trip.

#### Activation preconditions

1. The sleeve is defined by a snapshot, not by a specific order: at `STRATEGY_START_UTC` the sleeve consists of whatever BTC and USDG the account holds (`START_CAPITAL` = USDG quantity × $1.00 + BTC quantity × its Robinhood average cost). How they were acquired before that instant is irrelevant; sleeve free cash at the snapshot is $0.
2. All BTC and USDG activity strictly after `STRATEGY_START_UTC` belongs to this strategy; anything before it is ignored. On every run, verify the snapshot assumption still reconciles: snapshot quantities + fills since start must explain the current USDG and BTC quantities.
3. Do not enroll the sleeve's USDG in lending, staking, Earn, transfers, or any program that locks or moves it out of the immediately tradable Robinhood Crypto balance.
4. **Every BTC and USDG fill after `STRATEGY_START_UTC` belongs to the sleeve, whether the routine placed it or I placed it by hand, and whatever the order type.** A manual BTC buy is a legitimate sleeve entry at its actual fill cost (if several fills are open, `ENTRY` is their quantity-weighted average cost); a manual BTC sell is a legitimate sleeve exit; a manual USDG trade is a legitimate park/release. Continue the workflow from the resulting state — e.g. an unprotected manual BTC position gets its target or bear-exit sell on the very next run. Manual activity is never a reason to halt. Only crypto deposits, withdrawals, transfers, and rewards (quantity changes with no matching fill) make the ledger ambiguous → `INVALID_LEDGER`.
5. Never use more than the sleeve's reconstructed free cash and assets. Ignore unrelated account cash and holdings. BTC principal and all realized profits are swept back into USDG whenever they are not committed to a BTC entry or held in BTC.
6. Robinhood's tools supply BTC and USDG bid/ask, positions, and complete order/fill history. **Hourly candles come from the Coinbase Exchange public API** (see `CANDLE_SOURCE` below); Robinhood exposes no historical data. Orders and quotes used for execution still come only from Robinhood.


Use BTC for the directional trade and USDG only as the sleeve's parking asset. Do not trade any other cryptocurrency, stock, ETF, option, future, or event contract. Use default market-maker routing. **BTC orders (entry, target, bearish exit) are limit orders only. USDG conversions are market orders** (Robinhood accepts only market orders for USDG; it is a $1.00 stablecoin, so there is no price to protect). If an order review shows an explicit exchange-routing fee, a different routing mode, margin, borrowing, or an unexpected quantity or notional, abort that order and report.

### Core strategy

- Enter only in a bullish hourly regime: `SMA50 > SMA200`.
- While flat and bullish, keep one GTC limit buy resting at `ENTRY_LIMIT = HIGH_24H × (1 − PULLBACK)` — 1% below the highest completed hourly high of the last 24 hours. The buy fills only on a pullback, never while price is still pushing to new highs, so the sleeve does not chase the top. `HIGH_24H` rolls forward every hour, so in a steady uptrend the buy follows price up and a normal 1% dip fills it.
- After an entry fills, maintain one limit sell at 0.5% above the actual weighted-average fill price.
- If the hourly regime becomes bearish (`SMA50 <= SMA200`) before the target fills, exit at the current bid **only if that bid is at or above breakeven**; otherwise keep the profit target and hold. Never realize a loss.
- Hold at most one BTC position. Never average down, pyramid, or add to an existing position.
- Reinvest the strategy's capital after each completed lot, subject to the strategy-capital ledger below.

### B0 — Establish context on every run

1. Read the current UTC time. Set:
   - `CURRENT_HOUR_START` = beginning of the current UTC hour.
   - `LATEST_COMPLETE_HOUR` = the hourly candle ending at `CURRENT_HOUR_START`.
   - If invoked before minute 02 of an hour, report `CANDLE_NOT_SETTLED` and stop without placing an order.
2. Query the single agentic-enabled Robinhood account.
3. Confirm BTC is currently tradable. Crypto is normally continuous, but maintenance, account restrictions, or venue interruptions override the schedule. If not tradable, report and stop.
4. Snapshot all BTC-sleeve state:
   - BTC and USDG quantities, sellable quantities, and average costs.
   - Current BTC and USDG bid, ask, mark/estimated price, quote timestamp, and allowed price/quantity increments.
   - Every open BTC and USDG order, including asset, side, quantity/notional, limit price, time in force, routing, filled quantity, and order ID.
   - Every filled, cancelled, rejected, and partially filled BTC and USDG order since `STRATEGY_START_UTC`.
   - Account crypto buying power, but do not treat all account buying power as strategy capital.
5. Fetch hourly BTC candles with web fetch from `CANDLE_SOURCE` (fresh `start`/`end` each run). **Fetch in chunks of at most 72 candles** (three or four requests with consecutive `start`/`end` ranges covering the last 220 hours) — a full 300-candle page can come back summarized instead of raw. If a response is prose rather than a JSON array, re-request that chunk once with a narrower range; if it is still not raw JSON, treat the run as `CANDLES_UNAVAILABLE` and behave as for `STALE_CANDLES`. Parse the array; drop the bucket whose `time` equals `CURRENT_HOUR_START` (it is the incomplete current hour). Require at least 201 consecutive completed candles ending with `LATEST_COMPLETE_HOUR`, with timestamps plus open, high, low, close. Sort chronologically, remove exact duplicates, verify hourly continuity. **Freshness check:** the newest completed candle's `time` must equal `LATEST_COMPLETE_HOUR` − 1 h or later; if it is older, the response is cached or the source is lagging — retry once via `CANDLE_FALLBACK`, and if still stale report `STALE_CANDLES` and place no entry (protective sells in B4 still proceed using Robinhood quotes). If any of the last 200 required candles is missing, stop and report `INCOMPLETE_CANDLES`.
6. Spread guard: `SPREAD = (Robinhood BTC ask − bid) / ((ask + bid) / 2)`. If `SPREAD > MAX_SPREAD`, no new BTC entry may be placed this run (report `SPREAD_TOO_WIDE` with the numbers); existing positions and their sells are still managed.
7. Calculate only from completed candles:
   - `SMA50` = arithmetic mean of the latest 50 hourly closes.
   - `SMA200` = arithmetic mean of the latest 200 hourly closes.
   - `BULLISH = SMA50 > SMA200`.
   - `BEARISH = SMA50 <= SMA200`.
   - Never use the current incomplete hourly candle in either moving average.

### B1 — Reconstruct the strategy-capital ledger

Use actual BTC and USDG fills, never submitted order amounts.

1. Confirm no BTC/USDG fill is timestamped before `STRATEGY_START_UTC` and after the most recent fill that precedes it — i.e. the snapshot instant sits cleanly between activity.
2. `SLEEVE_FREE_CASH = total BTC/USDG sell proceeds − total BTC/USDG buy costs − all explicit sleeve fees` for every fill after `STRATEGY_START_UTC` (the starting USDG is an asset, not cash). This is a transaction-ledger balance, not account buying power.
2a. **Positions can lag fills.** `get_crypto_positions` has been observed to omit a BTC position minutes after its buy filled. Never derive `FLAT` from positions alone: if fills since start imply a BTC quantity that positions do not show, re-read positions once after 20 seconds; if still absent, treat the position as pending (`POSITION_PENDING`), place no BTC buy, and — if a sell is required — retry the position read on the next run rather than assuming the BTC is gone.
3. Pair BTC fills into chronological, non-overlapping lots. `BTC_REALIZED_PNL` = completed BTC sell proceeds minus their paired BTC costs and explicit BTC fees.
4. Treat all reconstructed BTC and USDG quantities as sleeve assets. `SLEEVE_BOOK_EQUITY = SLEEVE_FREE_CASH + actual cost basis of open BTC + open USDG quantity × $1.00`.
5. Allow small negative `SLEEVE_FREE_CASH` caused by rounding or by a manual buy that slightly exceeded released cash (treat the excess as additional sleeve capital and add it to `START_CAPITAL` for book-equity purposes). A negative balance is `INVALID_LEDGER` only if it cannot be explained by fills at all.
6. Never increase sleeve cash because unrelated account buying power is available.
7. If reconstructed BTC or USDG quantity differs materially from Robinhood after accounting for every fill (routine or manual), set state to `INVALID_LEDGER`; place no orders and report. Fills do not need to be "paired" — an open position simply has an average cost.

### B2 — Classify state

- `FLAT`: BTC quantity is zero and no BTC sell order is open.
- `PARKED_USDG`: BTC quantity is zero, no BTC entry is funded, and the sleeve is held in USDG.
- `USDG_RELEASE_WORKING`: BTC quantity is zero and a USDG market sell is still open (normally momentary) to fund a valid BTC entry.
- `ENTRY_FUNDED`: BTC quantity is zero, sleeve USDG has been sold, and sleeve free cash is available for one BTC entry order.
- `USDG_SWEEP_WORKING`: BTC quantity is zero and a USDG market buy is still open (normally momentary) to park free sleeve cash.
- `ENTRY_WORKING`: BTC quantity is zero and exactly one BTC limit buy is open.
- `LONG_TARGET`: BTC quantity is positive and exactly one BTC limit sell exists at the calculated profit target; no buy order or bearish-exit order is open.
- `LONG_UNPROTECTED`: BTC quantity is positive and no BTC sell order is open.
- `BEAR_EXIT_WORKING`: BTC quantity is positive and exactly one BTC sell order intended as the bearish exit is open.
- `PARTIAL_ENTRY`: a BTC buy is partially filled with an unfilled remainder.
- `PARTIAL_EXIT`: a BTC sell is partially filled with a remaining BTC position.
- `INVALID`: multiple BTC buy orders, simultaneous BTC buy and sell orders, more than one BTC sell order, overlapping USDG conversion orders, an order for more than the strategy-owned quantity/cash, a short crypto position, or any state not described above.
- `INVALID_LEDGER`: quantities cannot be explained by fills (a transfer, reward, or deposit moved crypto). Manual trades never cause this state.

For `INVALID` or `INVALID_LEDGER`, place no orders, describe the exact mismatch, and stop.

### B3 — Resolve fills and partial orders first

1. Refresh open orders and position immediately before acting. Never rely only on the initial snapshot.
2. If a target or bearish-exit order filled since the initial snapshot, treat the strategy as `FLAT`, record the completed lot and realized P&L, and continue to B5.
3. For a partial USDG conversion, cancel the unfilled remainder, poll until terminal, refresh USDG quantity and `SLEEVE_FREE_CASH`, and continue only from actual fills. Never assume USDG equals exactly $1.00.
4. `PARTIAL_ENTRY`:
   - Cancel the unfilled remainder of the buy.
   - Poll until the cancellation is confirmed or the order finishes filling.
   - Re-read the BTC position and calculate the weighted-average `ENTRY` from actual fills.
   - Manage the filled quantity as the complete current position; do not submit another buy to reach the intended size.
5. `PARTIAL_EXIT`:
   - Cancel the unfilled remainder.
   - Poll until cancellation or completion is confirmed.
   - Re-read the sellable BTC quantity.
   - If any BTC remains, place only the appropriate sell order for that remainder: target if bullish, bearish exit if bearish.
6. A rejected or cancelled order does not imply that no fill occurred. Always confirm filled quantity and position before submitting a replacement.

### B4 — Manage an open BTC position

Derive the current lot from filled orders:

- `QTY` = the entire sellable BTC quantity in the account.
- `ENTRY` = weighted-average price of all fills in the current entry.
- `TARGET_PX = ENTRY × 1.005`, rounded **up** to Robinhood's permitted BTC price increment.

#### B4a. Bearish regime — exit only at a profit

`BREAKEVEN_PX = ENTRY × (1 + 2 × FEE_RATE)` rounded up (the price at which a sell at the bid returns at least the total cost, including fees on both legs; with zero fees it is `ENTRY`).

If `BEARISH`:

1. Cancel every open BTC **buy** order and poll until terminal. No new entries while bearish.
2. If BTC is held and `current bid ≥ BREAKEVEN_PX`: the position is in profit, so take it now rather than wait for the full +0.5% — cancel the profit-target sell, confirm terminal, re-read the position, and place a limit sell for all sellable BTC at the current bid (`BEAR_EXIT_PX`). Poll up to three minutes: filled → record realized P&L, continue to B5; partial → `PARTIAL_EXIT`; unfilled → leave it working and reprice to the bid on each subsequent run **only while the bid stays ≥ BREAKEVEN_PX**; if the bid drops below breakeven, cancel the bear-exit and restore the profit target.
3. If BTC is held and `current bid < BREAKEVEN_PX`: **do not sell.** Keep (or place) the +0.5% profit-target sell at `TARGET_PX` and hold. This is deliberate: a bearish crossover is never a reason to realize a loss, even if that means holding through a long drawdown. Report `HOLDING_UNDERWATER_BEARISH` with entry, bid, and unrealized P&L.
4. A loss-making BTC sell is never placed by this routine under any regime. The only ways a position closes are the profit target, a bearish exit at or above breakeven, or a manual sell by me.

#### B4b. Bullish-regime profit target

If `BULLISH`:

1. Cancel any stale bearish-exit order and poll until terminal.
2. If no target order exists, review and place one GTC limit sell for all `QTY` at `TARGET_PX`. (This also applies when `BEARISH` and the bid is below breakeven — see B4a step 3.)
3. If one target exists at a different price or quantity, cancel it, confirm terminal state, refresh the position, and replace it with the correct target.
4. If the target already exists at the correct price and quantity, leave it unchanged.
5. Never place a second BTC buy while any BTC position remains.
6. After a confirmed full BTC exit, recalculate `SLEEVE_FREE_CASH`. If the regime is bullish, go straight to B5b and place the new entry buy from that cash (do not round-trip through USDG). Otherwise sweep all sleeve free cash into USDG under B5c.

### B5 — Manage the flat state and entry order

Run only after confirming BTC quantity is zero.

1. `HIGH_24H` = maximum high of the latest `HIGH_LOOKBACK` (24) completed hourly candles, ending with `LATEST_COMPLETE_HOUR`. Never include the current incomplete candle.
2. `ENTRY_LIMIT = HIGH_24H × (1 − PULLBACK)` = HIGH_24H × 0.99, rounded **down** to the permitted BTC price increment.
3. A standing BTC buy requires the sleeve to be funded in cash. USDG is not collateral and must be sold before placing the BTC order.
4. `BUY_QTY = floor(SLEEVE_FREE_CASH / ENTRY_LIMIT, Robinhood quantity precision)`.
5. Require `BUY_QTY > 0`, estimated notional at least Robinhood's minimum, and reviewed maximum cost no greater than `SLEEVE_FREE_CASH`.
6. If the ask is already at or below `ENTRY_LIMIT` when the buy is placed, it fills immediately at the ask or better — that is intended (price is already 1% or more below the 24-hour high). Never place a buy above `ENTRY_LIMIT`.

#### B5a. Bearish while flat

If `BEARISH`:

- Cancel any open BTC buy order and poll until terminal.
- Sweep all free sleeve cash into USDG under B5c.
- Place no entry order.
- Report SMA50, SMA200, their difference, HIGH_24H, and the entry price that would apply if the regime became bullish.

#### B5b. Bullish while flat

If `BULLISH`:

1. Maintain exactly one GTC BTC limit buy for `BUY_QTY` at `ENTRY_LIMIT`. If `SPREAD > MAX_SPREAD` or the candles are stale/unavailable, place no new buy and do not reprice an existing one; leave any working buy alone and report.
2. If the sleeve is parked in USDG and no BTC buy exists, cancel any stale USDG buy, then review and place a **market sell** for the entire strategy-owned USDG quantity (by quantity, not dollars). Poll until filled (up to three minutes). If it is not fully filled, cancel the remainder, refresh actual USDG and cash, and stop; do not use unrelated account cash. Use the actual fill proceeds, not USDG × $1.00, as the released cash.
3. Once `SLEEVE_FREE_CASH` is confirmed, review and place the BTC buy.
4. If a buy exists with a different price or quantity because `HIGH_24H` or sleeve cash changed, cancel it, confirm terminal state (if it filled during the cancel → B4), refresh position/cash, and replace it. In practice this happens at most once an hour, on the first run after a new hourly candle closes.
5. If the correct order already exists, leave it unchanged.
6. The buy fills only at its limit or better. Never convert it to a market order, and never raise it above `ENTRY_LIMIT`, however far price runs away.
7. If an entry fills, calculate `ENTRY` from actual fills and immediately place the B4b profit target after confirming the position. If the tool call sequence cannot complete, the next run must detect `LONG_UNPROTECTED` and place it.

#### B5c. USDG cash sweep

Use this whenever BTC is flat and sleeve cash will not remain committed to a resting BTC buy (bearish regime).

1. Cancel any open BTC buy and confirm its terminal state.
2. Reconstruct `SLEEVE_FREE_CASH` from fills. Never use total account buying power.
3. If `SLEEVE_FREE_CASH` is at least Robinhood's minimum crypto order, review and place a USDG **market buy** by dollar amount equal to `SLEEVE_FREE_CASH` rounded down to the cent. Confirm from the review that the estimated cost (including the ~1% market buy collar worst case) does not exceed sleeve cash plus $0.50; if it would, reduce the dollar amount by 1% and re-review.
4. Confirm the fill. If partially filled, cancel the remainder and keep the filled USDG. Never leave a USDG order open at the end of a run.
5. A USDG sweep is parking, not a trading signal. Never sell parked USDG except to fund a valid BTC entry.

### B6 — Order review and placement protocol

Before every order:

1. Refresh BTC and USDG positions, open orders, bid/ask, and the sleeve ledger.
2. Use the corresponding Robinhood `review_*_order` operation before `place_*_order`.
3. Confirm all of the following from the review:
   - asset is BTC for directional orders or USDG for the explicit parking conversions in B5;
   - side and quantity match the intended action;
   - order type is limit for BTC, market for USDG;
   - limit price and time in force are correct;
   - sell quantity does not exceed sellable BTC;
   - buy cost does not exceed `SLEEVE_FREE_CASH`;
   - no margin, borrowing, or unrelated account cash is required;
   - routing is market-maker routing and no explicit exchange-routing fee is shown.
4. Abort on any mismatch. Never edit the reviewed payload by assumption.
5. After placement, poll order state and re-read the position. An accepted order is not a fill.

### Hard rules — check before every BTC action

- BTC is the only directional asset; USDG is the only parking asset; long or flat only in each.
- At most one BTC position and one BTC order at a time, except transiently while a cancellation is being confirmed.
- Never average down, add to a position, pyramid, short BTC, use leverage, or borrow.
- BTC: limit orders only. USDG: market orders only. Never use a stop-market, recurring, or dollar-cost-averaging order.
- Profit targets are always calculated from actual weighted-average entry fills, never from quotes or submitted limits.
- The bearish regime is `SMA50 <= SMA200`; do not wait for a second crossover confirmation. A bearish regime blocks new entries and permits an early *profitable* exit; it never forces a loss.
- Never calculate an SMA from an incomplete candle, and never from candles that failed the freshness check.
- Candles are only ever used for the SMA indicators and `HIGH_24H`; every price used to place, size, or check an order comes from Robinhood quotes.
- Never infer a fill from price movement; confirm it from order status and position quantity.
- Never count unrelated cash, deposits, rewards, transfers, or holdings as strategy capital.
- Sweep idle BTC principal and realized profits into USDG, never SATA, BOXX, or another PARK asset.
- Never return BTC principal or gains to the equity sleeve, and never spend equity-sleeve cash (the equity rule excludes this sleeve's ledger cash from its own).
- Never touch TQQQ, XLK, VGT, SATA, BOXX, or any equity order, even if they appear in the account snapshot.
- Never cancel a correct working profit target or entry buy merely to refresh it.
- Any tool failure, stale quote, missing candle, unrecognized state, or nonterminal cancellation → stop and report. Do not retry blindly.

### Report (end of every run)

**All times in prose are Pacific Time** (`America/Los_Angeles`, e.g. "8:45 PM PT Wed Sep 23"). Never show UTC in prose; the JSON block may carry both `time_pt` and `timestamp_utc`. UTC is for internal calculations (candle buckets, `STRATEGY_START_UTC`) only.

1. Concise prose containing:
   - Pacific time and latest completed candle (stated in PT);
   - state and routing mode;
   - SMA50, SMA200, and bullish/bearish regime;
   - sleeve book equity, sleeve free cash, realized BTC P&L, BTC and USDG quantities, ENTRY, current bid/ask, and unrealized return;
   - HIGH_24H, ENTRY_LIMIT and spread when flat;
   - TARGET_PX when holding;
   - every cancellation, review, placement, partial fill, and confirmed fill;
   - anything skipped or flagged.
2. A fenced JSON object for comparison across runs:

```json
{
  "time_pt": "",
  "timestamp_utc": "",
  "latest_complete_hour": "",
  "state": "",
  "routing": "market_maker",
  "sma50": null,
  "sma200": null,
  "regime": "bullish|bearish|unknown",
  "strategy_start_capital": 1001.0,
  "parking_asset": "USDG",
  "btc_realized_pnl": null,
  "sleeve_free_cash": null,
  "sleeve_book_equity": null,
  "btc_qty": null,
  "usdg_qty": null,
  "entry": null,
  "bid": null,
  "ask": null,
  "spread": null,
  "high_24h": null,
  "entry_limit": null,
  "target_px": null,
  "open_orders": [],
  "orders_cancelled": [],
  "orders_placed": [],
  "fills": [],
  "flags": []
}
```
