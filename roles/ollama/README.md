# Role: ollama

## Purpose

Install, configure, and maintain the Ollama inference server on the AI server host.

## Installation

Ollama is installed using the official install script, which places the binary at
`/usr/local/bin/ollama` and creates a systemd service. The script handles both fresh
installs and upgrades.

## Environment Variables

Configuration is applied via a systemd drop-in override file at
`/etc/systemd/system/ollama.service.d/override.conf`.

| Variable                  | Value              | Description                                      |
|---------------------------|--------------------|--------------------------------------------------|
| `OLLAMA_HOST`             | `0.0.0.0:11434`   | Listen on all interfaces, port 11434             |
| `OLLAMA_MODELS`           | `/mnt/ai_data/ollama/models` | Model storage directory                |
| `OLLAMA_KEEP_ALIVE`       | `-1`               | Keep models loaded in GPU memory indefinitely    |
| `OLLAMA_NUM_PARALLEL`     | `4`                | Number of parallel inference requests            |
| `OLLAMA_MAX_LOADED_MODELS`| `4`                | Maximum models loaded in GPU memory at once      |
| `OLLAMA_API_KEY`          | (from Vault)       | API key for authentication                       |
| `OLLAMA_FLASH_ATTENTION`  | `1`                | Enable Flash Attention for performance           |
| `OLLAMA_CONTEXT_LENGTH`   | `32768`            | Default context window size                      |

## Override.conf Approach

Rather than modifying the upstream systemd unit file (which would be overwritten on
upgrades), this role uses a systemd drop-in directory:

```
/etc/systemd/system/ollama.service.d/override.conf
```

This ensures environment variables survive Ollama upgrades while keeping the
upstream service file intact.

## Why OLLAMA_API_KEY

Without an API key, anyone with network access to port 11434 can use the Ollama API
to run inference, pull models, or delete models. Setting `OLLAMA_API_KEY` requires
all API requests to include an `Authorization: Bearer <key>` header, preventing
unauthenticated access.

## OLLAMA_FLASH_ATTENTION

Flash Attention is a GPU memory optimization that reduces memory usage and increases
throughput for transformer inference. Setting `OLLAMA_FLASH_ATTENTION=1` enables
this optimization for all models. This is a newer addition to Ollama and provides
measurable performance improvements.

## Upgrade Procedure

To upgrade Ollama to the latest version:

```bash
ansible-playbook playbooks/03_ollama.yml
```

The official install script detects the existing installation and performs an
in-place upgrade. The service is restarted after the upgrade.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags ollama
```
