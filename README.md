# Agentic Money Minter

Rules-based trading instructions run by scheduled Claude routines against a Robinhood agentic account.

**Routine setup:** two hourly routines on this repository, one at cron `10 * * * *` and one at cron `40 * * * *` (together every 30 minutes, 24/7), both with the prompt:

> Follow all the rules in the repository, one after the other.

[`CLAUDE.md`](CLAUDE.md) defines the run order and how the rules interact; each rule decides for itself whether it has anything to do at the current time.

| Order | Rule | Active | Summary |
|---|---|---|---|
| 1 | [xlk-swing](rules/xlk-swing.md) | NYSE hours (6:30 AM–1:00 PM PT) | 100-share XLK swing parked in SATA (VGT/BOXX in December), with covered-call recovery and year-end close-out |
| 2 | [btc-usdg](rules/btc-usdg.md) | 24/7 | BTC trend sleeve parked in USDG: limit buy 1% below the 24-hour high while SMA50 > SMA200, +0.5% target, no-loss exits |
