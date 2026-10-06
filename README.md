# Agentic Money Minter

Rules-based trading instructions run by scheduled Claude routines against a Robinhood agentic account.

**Routine setup:** two hourly routines on this repository, one at cron `18 * * * *` and one at cron `48 * * * *` (together every 30 minutes, 24/7), both with the prompt:

> Follow all the rules in the repository, one after the other.

[`CLAUDE.md`](CLAUDE.md) defines the run order and how the rules interact; each rule decides for itself whether it has anything to do at the current time.

**Environment setup** (the cloud environment the routines run in → Edit):
- **Network access:** Custom, keep the default package managers, and allow `api.exchange.coinbase.com`, `api.kraken.com` (BTC candles) and `api.telegram.org` (reports).
- **Environment variables:** `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` (see below).

**Telegram reports:** every run sends a short human-readable summary of both rules (format in `CLAUDE.md` step 7) to Telegram via [`scripts/telegram-send.sh`](scripts/telegram-send.sh) (tests: `scripts/telegram-send_test.sh`).
1. In Telegram, message **@BotFather**, send `/newbot`, and follow the prompts; it gives you the bot token.
2. Open a chat with your new bot and send it any message (bots can only message you after you write to them).
3. In a browser, open `https://api.telegram.org/bot<token>/getUpdates` and copy `message.chat.id` — that is your chat ID.
4. Add both as environment variables in the routines' environment. Keep the token out of chats, commits and screenshots.

| Order | Rule | Active | Summary |
|---|---|---|---|
| 1 | [tqqq-swing](rules/tqqq-swing.md) | NYSE hours (6:30 AM–1:00 PM PT) | 100-share TQQQ swing parked in SATA, year-round: entries only while VIX > 16, +0.60% intraday target, covered-call recovery |
| 2 | [btc-usdg](rules/btc-usdg.md) | 24/7 | BTC trend sleeve parked in USDG: limit buy 1% below the 24-hour high while SMA50 > SMA200, +0.5% target, no-loss exits |
