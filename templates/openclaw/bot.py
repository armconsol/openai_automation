#!/usr/bin/env python3
"""OpenClaw — Telegram bot that proxies messages to Ollama."""

import sys
import logging
import yaml
import requests
from telegram import Update
from telegram.ext import ApplicationBuilder, MessageHandler, CommandHandler, filters, ContextTypes

CONFIG = {}


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    model = CONFIG["ollama"]["model"]
    await update.message.reply_text(
        f"Hello! I'm connected to Ollama using {model}. Send me any message."
    )


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = update.message.text

    if CONFIG["bot"].get("typing_indicator", True):
        await context.bot.send_chat_action(
            chat_id=update.effective_chat.id, action="typing"
        )

    try:
        resp = requests.post(
            f"{CONFIG['ollama']['base_url']}/api/generate",
            json={
                "model": CONFIG["ollama"]["model"],
                "prompt": text,
                "stream": False,
            },
            headers={"Authorization": f"Bearer {CONFIG['ollama']['api_key']}"},
            timeout=CONFIG["ollama"]["timeout"],
        )
        resp.raise_for_status()
        result = resp.json()["response"]

        max_len = CONFIG["bot"].get("max_message_length", 4096)
        if len(result) > max_len:
            result = result[:max_len]

    except Exception as e:
        logging.error("Ollama error: %s", e)
        result = CONFIG["bot"].get("error_message", "Sorry, I encountered an error.")

    await update.message.reply_text(result)


def main() -> None:
    global CONFIG

    config_path = "config.yml"
    if "--config" in sys.argv:
        config_path = sys.argv[sys.argv.index("--config") + 1]

    CONFIG = load_config(config_path)

    log_level = CONFIG.get("logging", {}).get("level", "INFO")
    logging.basicConfig(
        level=getattr(logging, log_level),
        format="%(asctime)s %(levelname)s %(message)s",
    )

    app = ApplicationBuilder().token(CONFIG["telegram"]["token"]).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    logging.info("OpenClaw starting with model: %s", CONFIG["ollama"]["model"])
    app.run_polling()


if __name__ == "__main__":
    main()
