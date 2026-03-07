# Role: hashi_vault

## Purpose

Deploy and configure HashiCorp Vault for centralized secret management across the
AI platform.

## Architecture

- Runs as a native systemd service on `ai_server` (`ai_server_ip`)
- Listens on `127.0.0.1:{{ vault_port }}` — not exposed directly
- TLS termination handled by NGINX reverse proxy on `nginx_proxy` (`nginx_proxy_ip`)
- Accessible at `https://vault.<domain>`

## Init Process

On first run, Vault is initialized with:

```
vault operator init -key-shares=1 -key-threshold=1
```

The unseal key and root token are saved to `vault/.vault-init.json`. This file is
gitignored and must never be committed to version control.

After init, Vault is automatically unsealed and an ansible-scoped token is written to
`vault/.vault-token` (also gitignored) for use by subsequent Ansible tasks.

## Secret Paths

All secrets are stored under `{{ vault_secret_prefix }}/` (default: `secret/data/ai-platform`).

| Secret                       | Path (relative to prefix) | Keys                                               |
|------------------------------|---------------------------|----------------------------------------------------|
| Ollama API key               | `/ollama`                 | `api_key`                                          |
| Keycloak credentials         | `/keycloak`               | `admin_password`, `client_secret`, `realm_admin_password`, `oidc_url` |
| Open WebUI secret key        | `/openwebui`              | `secret_key`                                       |
| OpenClaw Telegram token      | `/openclaw`               | `telegram_token`                                   |
| Vault OIDC client secret     | `/vault-oidc`             | `client_secret`                                    |

## Idempotency

Secrets are **only written if they do not already exist** in Vault. Re-running
`01_vault.yml` or `deploy_ai.yml` will never overwrite existing credentials.

This means the full `deploy_ai.yml` is safe to re-run at any time — running services
are not disrupted because their secrets never change unless explicitly rotated.

## Credential Rotation

To rotate a credential, delete its Vault path and re-run the deploy:

```bash
# Rotate a specific secret
vault kv delete secret/<vault_project_slug>/keycloak

# Re-run full deploy — new secret generated and all dependent services redeployed
ansible-playbook deploy_ai.yml -K -e @local.yml
```

Deletion forces regeneration on the next run. All services that depend on that
secret are automatically redeployed in the correct dependency order by `deploy_ai.yml`.

## Policies

### ansible-policy

Used by the `vault/.vault-token` ansible token for all Ansible lookups:

```hcl
path "{{ vault_secret_prefix }}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "{{ vault_secret_meta_prefix }}/*" {
  capabilities = ["list", "read", "delete"]
}
path "{{ vault_secret_meta_prefix }}" {
  capabilities = ["list"]
}
path "secret/metadata/" {
  capabilities = ["list"]
}
```

### vault-admin policy

Assigned to users who authenticate via Keycloak OIDC:

```hcl
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

## Keycloak OIDC Login

Vault is configured to accept Keycloak SSO via `playbooks/11_vault_oidc.yml`.

Only users with the `ai-admin` role in Keycloak can log in via OIDC. In the Vault UI:

1. Select method: **OIDC**
2. Role: **default**
3. Click **Sign in with OIDC Provider**
4. Authenticate via Keycloak

The OIDC client secret is stored at `{{ vault_secret_prefix }}/vault-oidc` and is
subject to the same idempotency rules as all other secrets.

## AppRole

An AppRole named `{{ vault_approle_name }}` (default: `ai-services`) is created for
container runtime access to secrets.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags vault
ansible-playbook playbooks/site.yml --tags vault-oidc
```
