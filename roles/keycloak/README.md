# Role: keycloak

## Purpose

Deploy Keycloak 24.x and configure the platform realm for single sign-on (SSO)
across all platform services.

## Container Configuration

| Setting                     | Value                                        |
|-----------------------------|----------------------------------------------|
| Image                       | `quay.io/keycloak/keycloak:latest`          |
| Port mapping                | `{{ keycloak_port }}:8080`                  |
| Volume                      | `/mnt/ai_data/keycloak:/opt/keycloak/data`  |
| Data directory ownership    | `1000:1000` (Keycloak container user)       |
| `KC_HOSTNAME`               | `https://idm.<domain>` (full URL required)  |
| `KC_PROXY_HEADERS`          | `xforwarded` (replaces deprecated KC_PROXY) |
| `KC_HTTP_ENABLED`           | `true` (TLS terminated at NGINX)            |
| `KEYCLOAK_ADMIN`            | `admin`                                     |
| `KEYCLOAK_ADMIN_PASSWORD`   | (from Vault)                                |

> **Note:** `KC_PROXY_HEADERS=xforwarded` replaces the deprecated `KC_PROXY=edge`
> from Keycloak 23 and earlier. The full URL format for `KC_HOSTNAME` is required
> in Keycloak 24+ to correctly generate HTTPS redirect URLs when behind a proxy.

## Realm Configuration

- **Realm name:** `{{ keycloak_realm }}` (default: `ai-platform`)
- **Display name:** `{{ keycloak_realm_display }}` (default: `AI Platform`)

### Clients

| Client ID    | Purpose                        | Redirect URIs                                  |
|--------------|--------------------------------|------------------------------------------------|
| `open-webui` | Open WebUI SSO                 | `https://ollama-ui.<domain>/*`                 |
| `vault`      | Vault UI OIDC login            | `https://vault.<domain>/ui/vault/auth/oidc/oidc/callback` |

The `vault` client is created by `playbooks/11_vault_oidc.yml`, not this playbook.
Both client secrets are stored in Vault.

### Roles

| Role       | Open WebUI             | Vault OIDC  | Description                 |
|------------|------------------------|-------------|-----------------------------|
| `ai-user`  | ✅ Standard access     | ❌ Blocked  | Standard AI platform user   |
| `ai-admin` | ✅ Admin access        | ✅ Full access | AI platform administrator |

Assign roles when creating users in the platform realm (not the `master` realm).

### Pre-created User

- **`{{ keycloak_realm_admin_user }}`** (default: `ai-platform-admin`) — created with
  the `ai-admin` role assigned. Password stored in Vault at
  `{{ vault_secret_prefix }}/keycloak:realm_admin_password`.

## Resetting Keycloak

If the Keycloak database needs to be wiped (e.g. admin password mismatch after
credential rotation), stop the container, remove the data directory, and re-run:

```bash
ssh <ai_server_ip> 'sudo docker stop keycloak; sudo docker rm keycloak; sudo rm -rf /mnt/ai_data/keycloak/*'
ansible-playbook playbooks/05_keycloak.yml -K -e @local.yml
ansible-playbook playbooks/11_vault_oidc.yml -K -e @local.yml
```

Keycloak will initialize from scratch using the current credentials in Vault.
Re-run `11_vault_oidc.yml` afterward to recreate the `vault` OIDC client.

## OIDC Endpoint

```
https://idm.<domain>/realms/<keycloak_realm>/.well-known/openid-configuration
```

## Admin Console

```
https://idm.<domain>/admin/
```

Log in with the `admin` user and the password stored in Vault at
`{{ vault_secret_prefix }}/keycloak:admin_password`.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags keycloak
```
