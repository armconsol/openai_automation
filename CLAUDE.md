# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Full deployment
ansible-playbook playbooks/site.yml

# Run a single playbook
ansible-playbook playbooks/03_benchmark.yml

# Run with tags (each playbook defines granular tags)
ansible-playbook playbooks/site.yml --tags ollama,docker

# Benchmark and update warm-up slots in one shot
ansible-playbook playbooks/03_benchmark.yml && ansible-playbook playbooks/04_models.yml

# Override slot 4 with a specific model
ansible-playbook playbooks/04_models.yml -e "slot4_model=qwen2.5-coder:7b"

# Run against a subset of hosts
ansible-playbook playbooks/09_nginx.yml --limit nginx_proxy

# Lint playbooks
ansible-lint playbooks/

# Install Galaxy dependencies
ansible-galaxy collection install -r requirements.yml

# Check mode (dry run)
ansible-playbook playbooks/site.yml --check --diff
```

## Required Local Configuration

Two gitignored files must exist before any playbook runs:

**`inventory/local.yml`** — per-host SSH overrides:
```yaml
all:
  hosts:
    ai_server:
      ansible_host: <actual_ip>
      ansible_user: <ssh_user>
    nginx_proxy:
      ansible_host: <actual_ip>
    coredns_host:
      ansible_host: <actual_ip>
```

**`local.yml`** — play-level variable overrides (domain, platform_name, SSL cert paths, etc.)

Vault runtime credentials live in `vault/.vault-token` and `vault/.vault-init.json` (written by `01_vault.yml` on first run).

## Architecture

### Three-Host Model

```
nginx_proxy (172.0.0.30)     — NGINX TLS termination for all public-facing services
ai_server (172.0.0.100)      — Ollama, Keycloak, Qdrant, Open WebUI, Vault, OpenClaw
coredns_host (172.0.0.29)    — CoreDNS zone file, Vault data mount
```

Vault runs on `ai_server` at `127.0.0.1:8202` only; NGINX proxies `https://vault.tftsr.com → ai_server:8202`. The same NGINX-as-TLS-terminator pattern applies to all services.

### Playbook Sequence

`site.yml` imports `00_preflight.yml` through `11_vault_oidc.yml` in order. Each can be run standalone. The canonical sequence matters for first-run because:
- `01_vault.yml` must precede all others (secrets don't exist yet)
- `05_keycloak.yml` must precede `07_openwebui.yml` (OIDC client_secret written to Vault by Keycloak role, read by OpenWebUI role)
- `03_benchmark.yml` must precede `04_models.yml` (produces `model_selection.json`)

### Secrets Flow

All credentials live exclusively in Vault under `secret/data/{{ vault_project_slug }}/*`. Playbooks retrieve them using either:
- `community.hashi_vault.hashi_vault` lookup plugin
- `ansible.builtin.uri` REST calls with `X-Vault-Token` header from `vault/.vault-token`

**Idempotency rule:** secrets are written to Vault only when the key does not already exist. Re-running never rotates credentials. To rotate: `vault kv delete secret/<slug>/<path>` then re-run the relevant playbook.

### Dynamic Benchmark → Model Slot Pipeline

`03_benchmark.yml` tests every locally-installed Ollama model against 6 prompts (3 coding, 3 general + 1 latency test), scores each, and writes `benchmarks/results/model_selection.json`. `04_models.yml` reads that JSON to decide which models to pull and keep warm.

**Composite score formula:**
```
composite = (quality × 0.45) + (tokens_per_sec / 30, capped at 1.0) × 0.30 + (1 - ttft_ms/5000, floored at 0) × 0.25
```

**Slot classification:** if `coding_composite - general_composite >= 0.15` (configurable via `benchmark_coding_threshold`), model goes to a coding slot; otherwise general.

**4 warm-up slots always hot in RAM:**
- Slots 1–2: top general-purpose models by composite score
- Slots 3–4: top coding models by composite score
- Slot 4 is user-rotatable via `-e slot4_model=<name>` without re-benchmarking

`04_models.yml` creates named Ollama Modelfiles (`coder-128k`, `coder-32k`, `llama-family`, `gemma-family`) and a `ollama-warmup.service` systemd one-shot that pre-loads all 4 slots after Ollama starts.

### Key Variables

All tuneable defaults live in `inventory/group_vars/all.yml`. The two most commonly changed clusters:

- **`candidate_models`** list — which models to auto-pull before benchmarking
- **`benchmark_thresholds`** block — min scores and normalization ceiling

`ollama_numa_node` and `ollama_cpu_affinity` are tuned for the Dell M630 dual-socket layout (NUMA node 1 holds ~120 GB free RAM); adjust these for other hardware.

### Docker Services

Keycloak, Qdrant, and Open WebUI run as Docker containers managed by `community.docker.docker_container`. Service-to-service calls use `host.docker.internal` (Docker bridge). Ollama and Vault run as native systemd services, not containers.
