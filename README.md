# Agentic Money Minter

Rules-based trading prompts run as scheduled routines against a Robinhood agentic account.
Each rule in `rules/` is a self-contained prompt: paste the **Prompt** section into the routine
and set the schedule described at the top of the file.

| Rule | Schedule | Summary |
|---|---|---|
| [equity-swing-btc-usdg-combined](rules/equity-swing-btc-usdg-combined.md) | Hourly at :03 and :33, 24/7 | XLK/SATA swing (VGT/BOXX in December) during NYSE hours; BTC/USDG dip-buy sleeve off-hours |
