# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

```bash
# Full deployment
ansible-playbook playbooks/site.yml -K -e @local.yml

# Run a single playbook
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml

# Run with tags (each playbook defines granular tags)
ansible-playbook playbooks/site.yml --tags ollama,docker -K -e @local.yml

# Benchmark and update warm-up slots in one shot
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml && \
ansible-playbook playbooks/04_models.yml -K -e @local.yml

# Rotate general slot (Node 1, port 11434)
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot5_model=mistral:latest"

# Rotate coding slot (Node 0, port 11435)
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot6_model=llama3.1:70b"

# Run against a subset of hosts
ansible-playbook playbooks/09_nginx.yml --limit nginx_proxy -K -e @local.yml

# Lint playbooks
ansible-lint playbooks/

# Install Galaxy dependencies
ansible-galaxy collection install -r requirements.yml

# Check mode (dry run)
ansible-playbook playbooks/site.yml --check --diff -K -e @local.yml
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
composite = (quality × 0.45) + (tokens_per_sec / ceiling, capped at 1.0) × 0.30 + (1 - ttft_ms/5000, floored at 0) × 0.25
```
`benchmark_toks_norm_ceiling` defaults to 40 (dual-socket target).

**Slot classification:** if `coding_composite - general_composite >= 0.10` (configurable via `benchmark_coding_threshold`), model goes to a coding slot; otherwise general.

**6 warm-up slots across two NUMA instances:**
- Node 1 (port 11434): slots 1–2 locked general + slot 5 rotatable general
- Node 0 (port 11435): slots 3–4 locked coding + slot 6 rotatable coding
- Slots 5/6 rotatable via `-e slot5_model=<name>` / `-e slot6_model=<name>` without re-benchmarking

`04_models.yml` creates Modelfiles (`coder-128k`, `coder-32k`, `coder-rotate`, `llama-family`, `gemma-family`) and two warmup services: `ollama-warmup.service` (Node 1) and `ollama-warmup-node0.service` (Node 0).

**Benchmark alias filter:** `benchmark_skip_aliases` in `group_vars/all.yml` lists the Modelfile aliases — the benchmark playbook excludes these from the test loop to prevent 32k-token KV-cache allocations from stalling the run.

### Key Variables

All tuneable defaults live in `inventory/group_vars/all.yml`. The two most commonly changed clusters:

- **`candidate_models`** list — which models to auto-pull before benchmarking
- **`benchmark_thresholds`** block — min scores and normalization ceiling

`ollama_numa_node` and `ollama_cpu_affinity` are tuned for the Dell M630 dual-socket layout (NUMA node 1 holds ~120 GB free RAM); adjust these for other hardware.

### Docker Services

Keycloak, Qdrant, and Open WebUI run as Docker containers managed by `community.docker.docker_container`. Service-to-service calls use `host.docker.internal` (Docker bridge). Ollama and Vault run as native systemd services, not containers.
