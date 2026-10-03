# Agentic Money Minter

Rules-based trading prompts run as scheduled routines against a Robinhood agentic account.
Each rule in `rules/` is a self-contained prompt: paste the **Prompt** section into the routine
and set the schedule described at the top of the file.

| Rule | Schedule | Summary |
|---|---|---|
| [xlk-swing](rules/xlk-swing.md) | :15 and :45, 6 AM–12 PM PT, NYSE weekdays | 100-share XLK swing parked in SATA (VGT/BOXX in December), with covered-call recovery and year-end close-out |
| [btc-usdg](rules/btc-usdg.md) | :05 and :35, 24/7 | BTC trend sleeve parked in USDG: limit buy 1% below the 24-hour high while SMA50 > SMA200, +0.5% target, no-loss exits |
