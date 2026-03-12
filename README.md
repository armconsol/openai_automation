# ai-platform -- Local AI Server Automation

Ansible automation for full lifecycle management of a server as a
local AI inference platform. This project provisions, configures, benchmarks, and
maintains every service required to run Ollama-based LLM inference behind NGINX
reverse proxy with SSO, vector search (RAG), DNS, secret management, and Telegram
bot access -- all driven by a single `ansible-playbook deploy_ai.yml` command.

## Architecture

```
                         ┌──────────────┐
                         │   Internet   │
                         └──────┬───────┘
                                │
                       ┌────────▼────────┐
                       │  nginx_proxy    │
                       │  192.168.1.30   │
                       │  NGINX reverse  │
                       │  proxy + TLS    │
                       └──┬──────────┬───┘
                          │          │
          ┌───────────────▼┐    ┌────▼──────────────────────┐
          │ coredns_host   │    │ ai_server                 │
          │ 192.168.1.29   │    │ 192.168.1.100             │
          │                │    │                           │
          │ - CoreDNS      │    │ - Ollama (LLM inference)  │
          └────────────────┘    │ - Open WebUI              │
                                │ - Keycloak (SSO/OIDC)     │
                                │ - HashiCorp Vault         │
                                │ - Qdrant (vector DB)      │
                                │ - OpenClaw (Telegram bot) │
                                └───────────────────────────┘
```

## Infrastructure Map

| Host           | IP Address     | Purpose                          |
|----------------|----------------|----------------------------------|
| `nginx_proxy`  | 192.168.1.30   | NGINX reverse proxy, TLS termination |
| `coredns_host` | 192.168.1.29   | CoreDNS                          |
| `ai_server`    | 192.168.1.100  | Ollama, Open WebUI, Keycloak, Vault, Qdrant, OpenClaw |

> These are the **default** values in `inventory/group_vars/all.yml`. Override for your environment — see [Configuration](#configuration) below.

## Service URLs

| Service    | URL (default `domain: example.com`)       |
|------------|-------------------------------------------|
| Open WebUI | https://ollama-ui.example.com             |
| Ollama API | https://ollama-api.example.com            |
| Keycloak   | https://idm.example.com                   |
| Vault      | https://vault.example.com                 |

## Configuration

All environment-specific values are variables with generic defaults in
`inventory/group_vars/all.yml`. Override them in `local.yml` (gitignored).

| Variable            | Default                              | Description                                         |
|---------------------|--------------------------------------|-----------------------------------------------------|
| `domain`            | `example.com`                        | Base domain for all service URLs                    |
| `ai_server_ip`      | `192.168.1.100`                      | IP of the AI inference server                       |
| `nginx_proxy_ip`    | `192.168.1.30`                       | IP of the NGINX reverse proxy                       |
| `coredns_host_ip`   | `192.168.1.29`                       | IP of the CoreDNS host                              |
| `ansible_user`      | `admin`                              | SSH user on all managed hosts                       |
| `platform_name`     | `"AI Platform"`                      | Display name used in WebUI, Keycloak, and summaries |
| `vault_project_slug`| `"ai-platform"`                      | Slug for Keycloak realm name and Vault secret paths |
| `nginx_ssl_cert`    | `/etc/nginx/ssl/{{ domain }}.crt`    | Path to TLS certificate on nginx_proxy              |
| `nginx_ssl_key`     | `/etc/nginx/ssl/{{ domain }}.key`    | Path to TLS private key on nginx_proxy              |

> If you use Let's Encrypt, override `nginx_ssl_cert` and `nginx_ssl_key` in
> `local.yml` to point to your certbot paths (e.g.
> `/etc/letsencrypt/live/your-domain/fullchain.pem`).

### Setup: two gitignored local files

Configuration is split across two gitignored files — create both before first run.

**`inventory/local.yml`** — SSH connection details (host IPs and user):

```yaml
# inventory/local.yml
all:
  hosts:
    ai_server:
      ansible_host: 10.0.1.50
      ansible_user: myuser
    nginx_proxy:
      ansible_host: 10.0.1.10
      ansible_user: myuser
    coredns_host:
      ansible_host: 10.0.1.9
      ansible_user: myuser
```

Ansible reads the `inventory/` directory automatically (`ansible.cfg` sets
`inventory = inventory/`), so `inventory/local.yml` is merged with
`inventory/hosts.yml` on every run — no extra flags needed.

The `inventory/` directory also contains `group_vars/` and `host_vars/`, which
ensures Ansible finds them regardless of which playbook is run directly.

**`local.yml`** — play variables (domain, platform identity, SSL certs, etc.):

```yaml
# local.yml
domain: mylab.internal
ai_server_ip: 10.0.1.50
nginx_proxy_ip: 10.0.1.10
coredns_host_ip: 10.0.1.9
platform_name: "My AI Platform"
vault_project_slug: my-ai
nginx_ssl_cert: /etc/letsencrypt/live/mylab.internal/fullchain.pem
nginx_ssl_key: /etc/letsencrypt/live/mylab.internal/privkey.pem
```

> `ai_server_ip`, `nginx_proxy_ip`, and `coredns_host_ip` appear in both files.
> `inventory/local.yml` controls where Ansible SSHs to; `local.yml` controls what
> gets rendered into config files and DNS records.

### Alternative: inline `-e` flags (no local.yml)

```bash
ansible-playbook deploy_ai.yml -K \
  -e "domain=mylab.internal" \
  -e "ai_server_ip=10.0.1.50" \
  -e "nginx_proxy_ip=10.0.1.10" \
  -e "coredns_host_ip=10.0.1.9" \
  -e "platform_name='My AI Platform'" \
  -e "vault_project_slug=my-ai" \
  -e "nginx_ssl_cert=/etc/letsencrypt/live/mylab.internal/fullchain.pem" \
  -e "nginx_ssl_key=/etc/letsencrypt/live/mylab.internal/privkey.pem"
```

> `inventory/local.yml` must still exist for SSH to work — inline `-e` flags
> cannot set per-host connection variables.

## Prerequisites

- Ansible 2.14+
- Python 3.9+
- SSH access to all 3 hosts
- sudo privileges on all 3 hosts
- Ansible Galaxy collections:

```bash
ansible-galaxy collection install -r requirements.yml
```

## First-Run Quickstart

```bash
git clone <repo>
cd ai-platform
ansible-galaxy collection install -r requirements.yml

# 1. Create inventory/local.yml with your host IPs and SSH user (gitignored)
# 2. Create local.yml with your domain, platform name, SSL cert paths, etc. (gitignored)
# See the Configuration section above for the contents of each file.

# 3. Deploy
ansible-playbook deploy_ai.yml -K -e @local.yml
```

> `-K` prompts for the sudo (become) password on the remote hosts.

## Credential Management

All secrets (API keys, passwords, OIDC client secrets) are stored in HashiCorp Vault
and **only written once** — re-running any playbook will never overwrite an existing
secret. This means `deploy_ai.yml` is safe to re-run at any time without breaking
running services.

### Credential rotation

To rotate a specific credential, delete it from Vault and re-run the full deploy:

```bash
# Example: rotate Keycloak credentials
vault kv delete secret/<vault_project_slug>/keycloak
ansible-playbook deploy_ai.yml -K -e @local.yml
```

New credentials will be generated, stored in Vault, and all dependent services
(Keycloak, Open WebUI, Vault OIDC) will be redeployed in the correct order automatically.

### Vault login

Vault UI supports two login methods:

- **Token** — use the root token from `vault/.vault-init.json` (emergency/admin use only)
- **OIDC** — select method `OIDC`, role `default`, click *Sign in with OIDC Provider*,
  authenticate via Keycloak. Only users with the `ai-admin` Keycloak role can log in.

## User Roles

Users are created in Keycloak at `https://idm.<domain>/admin/`. Assign roles
from the platform realm (not the `master` realm):

| Role       | Open WebUI             | Vault OIDC  |
|------------|------------------------|-------------|
| `ai-user`  | ✅ Standard access     | ❌ Blocked  |
| `ai-admin` | ✅ Admin access        | ✅ Full access |
| *(none)*   | ❌ Blocked             | ❌ Blocked  |

## Connecting Coding Agents

The platform exposes two API endpoints for coding tools (aider, Continue.dev, Cursor, etc.).
**Users should connect via Open WebUI** — it enforces Keycloak authentication and issues
per-user API keys. Direct Ollama access is for service accounts and admin use only.

### Option A — Via Open WebUI (recommended for users)

Each user authenticates through Keycloak and has their own API key. Open WebUI exposes an
OpenAI-compatible API that all major coding agent tools support.

**Step 1 — Generate your personal API key:**

1. Browse to `https://ollama-ui.<domain>` and log in via SSO
2. Click your avatar (top-right) → **Settings** → **Account**
3. Scroll to **API Keys** → **Create new secret key**
4. Copy the key — it is only shown once

**Step 2 — Configure your coding tool:**

| Setting   | Value                                  |
|-----------|----------------------------------------|
| Base URL  | `https://ollama-ui.<domain>/api`       |
| API key   | your personal Open WebUI key           |
| Model     | any model name shown in the WebUI      |

**Aider:**
```bash
aider --openai-api-base https://ollama-ui.<domain>/api \
      --openai-api-key  <your-openwebui-key> \
      --model           deepseek-coder-v2:latest
```

**Continue.dev** (`~/.continue/config.json`):
```json
{
  "models": [
    {
      "title": "AI Platform",
      "provider": "openai",
      "model": "deepseek-coder-v2:latest",
      "apiBase": "https://ollama-ui.<domain>/api",
      "apiKey": "<your-openwebui-key>"
    }
  ]
}
```

**Cursor / VS Code** — add a custom OpenAI-compatible provider pointing to
`https://ollama-ui.<domain>/api` with your personal key.

---

### Option B — Direct Ollama API (admin / service accounts only)

The Ollama API endpoint is protected by a single shared key stored in Vault. It is
intended for internal service-to-service calls and admin use — not for individual users.

**Retrieve the Ollama API key from Vault:**
```bash
vault kv get -field=api_key secret/<vault_project_slug>/ollama
```

| Setting   | Value                                  |
|-----------|----------------------------------------|
| Base URL  | `https://ollama-api.<domain>/v1`       |
| API key   | Ollama API key from Vault              |
| Model     | any installed Ollama model name        |

**Aider:**
```bash
aider --openai-api-base https://ollama-api.<domain>/v1 \
      --openai-api-key  <ollama-api-key> \
      --model           deepseek-coder-v2:latest
```

> **Note:** Direct Ollama access bypasses Keycloak auth and usage tracking.
> Rotate the key via `vault kv delete secret/<vault_project_slug>/ollama` and
> re-run `playbooks/02_infrastructure.yml`.

---

### Recommended models for coding

The benchmark playbook automatically selects the best coding models and keeps them warm.
Check the current slot assignments in `benchmarks/results/model_selection.json`:

```bash
python3 -m json.tool benchmarks/results/model_selection.json | grep slot
```

Slots 3–6 are coding-classified models, all running on the Node 0 instance at port 11435.
Use `slot3_coding` (the highest-scoring coding model) as your primary model. Connect coding
tools directly to `https://ollama-api.<domain>` (proxied from port 11434, Node 1) or to
Open WebUI which load-balances across both instances.

## Day-2 Operations

**Full deploy / idempotent re-run:**

```bash
ansible-playbook deploy_ai.yml -K -e @local.yml
```

**Pre-flight checks only:**

```bash
ansible-playbook deploy_ai.yml -K -e @local.yml --tags preflight
```

**Skip benchmarking on re-runs (faster):**

```bash
ansible-playbook deploy_ai.yml -K -e @local.yml --skip-tags benchmark
```

**Vault only:**

```bash
ansible-playbook playbooks/01_vault.yml -K -e @local.yml
```

**Docker + Ollama only:**

```bash
ansible-playbook playbooks/02_infrastructure.yml -K -e @local.yml
```

**Re-benchmark all installed models:**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml
```

**Benchmark specific models only:**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_models=qwen2.5-coder:14b-instruct-q4_K_M,codestral:22b-v0.1-q4_K_M"
```

**Override tier boundaries or timeouts (see [benchmarks/README.md](benchmarks/README.md#three-pass-execution)):**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_small_max_gb=8 benchmark_medium_max_gb=20"
```

**Pull recommended models if scores are below threshold:**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml -e "pull_if_better=true"
```

**Update warm-up slots after a benchmark:**

```bash
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

**Rotate slot 5 (general) or slot 6 (coding) to a specific model:**

```bash
# Swap general rotate slot
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot5_model=mistral:latest"

# Swap coding rotate slot
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot6_model=llama3.1:70b"

# Both at once
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot5_model=mistral:latest" -e "slot6_model=command-r:35b"

# Reset both rotate slots back to benchmark recommendations
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

**Redeploy Keycloak only:**

```bash
ansible-playbook playbooks/05_keycloak.yml -K -e @local.yml
```

**Redeploy Open WebUI only:**

```bash
ansible-playbook playbooks/07_openwebui.yml -K -e @local.yml
```

**Update NGINX configs only:**

```bash
ansible-playbook playbooks/09_nginx.yml -K -e @local.yml
```

**Update CoreDNS records only:**

```bash
ansible-playbook playbooks/10_coredns.yml -K -e @local.yml
```

**Configure Keycloak SSO login for Vault UI:**

```bash
ansible-playbook playbooks/11_vault_oidc.yml -K -e @local.yml
```

## Model Slot System

Six models are kept warm across two Ollama instances (`OLLAMA_MAX_LOADED_MODELS=3` each, `OLLAMA_KEEP_ALIVE=-1`). Slots are filled automatically by the benchmark playbook — no model names are hardcoded.

```
NUMA Node 1 — ollama.service     — port 11434  (general models)
NUMA Node 0 — ollama-node0.service — port 11435 (coding models)
```

| Slot | Instance      | Port  | Role                    | Selection                     | Rotation                                    |
|------|---------------|-------|-------------------------|-------------------------------|---------------------------------------------|
| 1    | Node 1        | 11434 | General primary (locked) | Top general composite score  | Replaced only by re-benchmark               |
| 2    | Node 1        | 11434 | General secondary (locked)| 2nd general composite score | Replaced only by re-benchmark               |
| 5    | Node 1        | 11434 | General rotate           | 3rd general composite score   | `-e slot5_model=<name>`                     |
| 3    | Node 0        | 11435 | Coding primary (locked)  | Top coding composite score    | Replaced only by re-benchmark               |
| 4    | Node 0        | 11435 | Coding secondary (locked)| 2nd coding composite score    | Replaced only by re-benchmark               |
| 6    | Node 0        | 11435 | Coding rotate            | 3rd coding composite score    | `-e slot6_model=<name>`                     |

**Classification rule:** a model is classified `coding` if its coding composite score exceeds its general composite score by ≥ 0.10; otherwise `general`.

**Modelfile aliases** (`coder-128k`, `coder-32k`, `coder-rotate`, `llama-family`, `gemma-family`) are excluded from benchmarking to prevent KV-cache allocation stalls.

## Verification Steps

After a full `deploy_ai.yml` run, verify the deployment (substitute your actual `domain` and IPs):

1. **Vault health** -- `curl -s https://vault.example.com/v1/sys/health` returns `initialized: true, sealed: false`
2. **Vault OIDC login** -- select OIDC method, role `default`, authenticate with an `ai-admin` Keycloak user
3. **Ollama API** -- `curl -s https://ollama-api.example.com/api/tags` returns model list
4. **Open WebUI** -- browse to https://ollama-ui.example.com, SSO login works with `ai-user` or `ai-admin`
5. **Keycloak admin** -- browse to https://idm.example.com/admin/, login with `admin` credentials from Vault
6. **Qdrant health** -- `curl -s http://<ai_server_ip>:6333/healthz` returns OK
7. **CoreDNS resolution** -- `dig @<coredns_host_ip> vault.example.com` returns `<nginx_proxy_ip>`
8. **NGINX configs** -- `ssh <nginx_proxy_ip> 'sudo nginx -t'` passes
9. **OpenClaw** -- send a message to the Telegram bot, confirm response using slot1_general model
10. **Benchmark report** -- check `benchmarks/results/benchmark_<timestamp>.md` for latest results
11. **Node 0 Ollama** -- `curl -s -H "Authorization: Bearer <key>" http://<ai_server_ip>:11435/api/tags` returns model list
12. **Both warmup services** -- `systemctl status ollama-warmup ollama-warmup-node0` both show `active (exited)`

## Role Reference

| Role         | README                                  | Purpose                        |
|--------------|-----------------------------------------|--------------------------------|
| preflight    | [roles/preflight/README.md](roles/preflight/README.md)   | Pre-flight validation          |
| hashi_vault  | [roles/hashi_vault/README.md](roles/hashi_vault/README.md) | HashiCorp Vault deployment     |
| docker       | [roles/docker/README.md](roles/docker/README.md)         | Docker CE installation         |
| ollama       | [roles/ollama/README.md](roles/ollama/README.md)         | Ollama inference server        |
| benchmark    | [roles/benchmark/README.md](roles/benchmark/README.md)   | Model benchmarking             |
| models       | [roles/models/README.md](roles/models/README.md)         | Model lifecycle management     |
| keycloak     | [roles/keycloak/README.md](roles/keycloak/README.md)     | Keycloak SSO/OIDC              |
| qdrant       | [roles/qdrant/README.md](roles/qdrant/README.md)         | Qdrant vector database         |
| openwebui    | [roles/openwebui/README.md](roles/openwebui/README.md)   | Open WebUI deployment          |
| openclaw     | [roles/openclaw/README.md](roles/openclaw/README.md)     | OpenClaw Telegram bot          |
| nginx        | [roles/nginx/README.md](roles/nginx/README.md)           | NGINX reverse proxy            |
| coredns      | [roles/coredns/README.md](roles/coredns/README.md)       | CoreDNS zone management        |

## Security Notes

- `vault/.vault-init.json` and `vault/.vault-token` are gitignored -- they contain
  Vault unseal keys and root tokens. **Never commit these files.**
- `local.yml` and `inventory/local.yml` are gitignored -- they contain your
  environment-specific IPs, usernames, and cert paths. **Never commit these files.**
- All service secrets (database passwords, API keys, OIDC client secrets) are stored
  in HashiCorp Vault and injected at deploy time. Secrets are never regenerated unless
  explicitly deleted from Vault.
- Ollama API is protected by `OLLAMA_API_KEY` to prevent unauthenticated access.
- TLS termination happens at the NGINX reverse proxy layer.
- Open WebUI and Vault UI both require a valid Keycloak role to access via SSO.
