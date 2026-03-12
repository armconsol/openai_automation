# Role: openclaw

## Purpose

Deploy OpenClaw, a Telegram bot that provides access to Ollama models via Telegram
messaging. Always uses the best warm general-purpose model (`slot1_general` from the
last benchmark run).

## Prerequisites

- A Telegram bot token obtained from [@BotFather](https://t.me/BotFather)
- The token must be stored in Vault at `{{ vault_secret_prefix }}/openclaw:telegram_token`
- `benchmarks/results/model_selection.json` must exist (produced by `03_benchmark.yml`)

## Model Selection

`08_openclaw.yml` reads `benchmarks/results/model_selection.json` at deploy time and
sets `openclaw_model` to `slot1_general` — the highest-scoring general model that is
always warm on the Node 1 instance (port 11434). This ensures the bot always uses the
best available model without requiring manual updates after a benchmark run.

The fallback value (used when `model_selection.json` is absent) is set in
`inventory/group_vars/all.yml` under `openclaw_model`.

## Ollama Endpoint

OpenClaw connects to `localhost:11434` — the Node 1 general instance. Coding models on
port 11435 are not accessible to the bot; they are reserved for IDE and API integrations.

## Installation

1. Python 3 dependencies (`python-telegram-bot`, `requests`, `pyyaml`) are installed via `pip3`
2. The bot script is deployed to `/mnt/ai_data/openclaw/bot.py`
3. Config is templated to `/mnt/ai_data/openclaw/config.yml`
4. A systemd service (`openclaw.service`) manages the process

## Configuration

Config file location: `/mnt/ai_data/openclaw/config.yml`

The configuration includes:
- Ollama API endpoint (`http://localhost:11434`) and API key (from Vault)
- Telegram bot token (from Vault)
- Model name (from `slot1_general`)

## Vault Integration

- **Path:** `{{ vault_secret_prefix }}/openclaw`
- **Key:** `telegram_token`

The Telegram token is read from Vault at deploy time and written to the config file.

## Skipping Installation

If no Telegram bot token is configured (Vault secret absent or empty), the entire
OpenClaw installation is skipped. This allows running `site.yml` without a Telegram
bot token.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags openclaw -K -e @local.yml
ansible-playbook playbooks/08_openclaw.yml -K -e @local.yml
```
