# Role: openclaw

## Purpose

Deploy OpenClaw, a Telegram bot that provides access to Ollama models via Telegram
messaging.

## Prerequisites

- A Telegram bot token obtained from [@BotFather](https://t.me/BotFather)
- The token must be stored in Vault at `{{ vault_secret_prefix }}/openclaw:telegram_token`

## Installation

1. Node.js 20 is installed on the target host
2. OpenClaw is installed globally via `npm install -g openclaw`
3. A systemd service (`openclaw.service`) is created for process management

## Configuration

Config file location: `/mnt/ai_data/openclaw/config.yml`

The configuration includes:

- Ollama API endpoint and authentication
- Telegram bot token (read from Vault)
- Default model selection
- Allowed user IDs (if access control is needed)

## Service

```
/etc/systemd/system/openclaw.service
```

The service runs as a systemd unit, automatically starting on boot and restarting
on failure.

## Vault Integration

The Telegram bot token is stored in Vault:

- **Path:** `{{ vault_secret_prefix }}/openclaw`
- **Key:** `telegram_token`

The role reads the token from Vault at deploy time and writes it to the config file.

## Skipping Installation

If no Telegram bot token is configured (the Vault secret is empty or absent),
the OpenClaw installation is skipped entirely during `site.yml`. This allows
running the full playbook without a Telegram bot token if the feature is not needed.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags openclaw
```
