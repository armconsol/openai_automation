# Role: openwebui

## Purpose

Deploy Open WebUI with full Ollama integration, RAG support via Qdrant, and SSO via
Keycloak OIDC.

## Environment Variables

| Variable                      | Value                                                        | Source      |
|-------------------------------|--------------------------------------------------------------|-------------|
| `OLLAMA_BASE_URL`             | `http://host.docker.internal:11434`                         | Hardcoded   |
| `OLLAMA_API_KEY`              | (Ollama API key)                                             | Vault       |
| `WEBUI_SECRET_KEY`            | (session signing key)                                        | Vault       |
| `VECTOR_DB`                   | `qdrant`                                                     | Hardcoded   |
| `QDRANT_URI`                  | `http://host.docker.internal:6333`                          | Hardcoded   |
| `ENABLE_RAG_WEB_SEARCH`      | `true`                                                       | Hardcoded   |
| `OAUTH_CLIENT_ID`            | `open-webui`                                                 | Hardcoded   |
| `OAUTH_CLIENT_SECRET`        | (OIDC client secret)                                         | Vault       |
| `OPENID_PROVIDER_URL`        | `https://idm.<domain>/realms/<keycloak_realm>/.well-known/openid-configuration` | Vault (keycloak_oidc_url) |
| `OAUTH_PROVIDER_NAME`        | `{{ platform_name }}`                                        | group_vars  |
| `ENABLE_OAUTH_SIGNUP`        | `true`                                                       | Hardcoded   |
| `DEFAULT_USER_ROLE`          | `user`                                                       | Hardcoded   |
| `WEBUI_NAME`                 | `{{ platform_name }}`                                        | group_vars  |
| `ENABLE_OAUTH_ROLE_MANAGEMENT` | `true`                                                     | Hardcoded   |
| `OAUTH_ROLES_CLAIM`          | `realm_access.roles`                                         | Hardcoded   |
| `OAUTH_ALLOWED_ROLES`        | `ai-user,ai-admin`                                           | Hardcoded   |
| `OAUTH_ADMIN_ROLES`          | `ai-admin`                                                   | Hardcoded   |

## OIDC Setup

Open WebUI uses Keycloak as its OIDC provider:

1. `OAUTH_CLIENT_ID` is set to `open-webui` (matching the Keycloak client)
2. `OAUTH_CLIENT_SECRET` is read from Vault at `{{ vault_secret_prefix }}/keycloak:client_secret`
3. `OPENID_PROVIDER_URL` points to the Keycloak OIDC discovery endpoint

## RAG

- **Vector DB:** Qdrant at `http://host.docker.internal:6333`
- **Web search:** enabled via `ENABLE_RAG_WEB_SEARCH=true`
- Users can upload documents through the Open WebUI interface for RAG-augmented
  conversations

## Model Access

Open WebUI connects to Ollama at `http://host.docker.internal:11434` (the Docker
host network). The `OLLAMA_API_KEY` environment variable authenticates API requests
to the Ollama server.

## SSO

Users see a "Sign in with {{ platform_name }}" button on the login page. Clicking it
redirects to the Keycloak login page for the `{{ keycloak_realm }}` realm. After
authentication, users are redirected back to Open WebUI.

Access is restricted by Keycloak realm role:

| Keycloak role | Open WebUI access      |
|---------------|------------------------|
| `ai-user`     | ✅ Standard user       |
| `ai-admin`    | ✅ Admin               |
| *(none)*      | ❌ Login blocked       |

New users who authenticate via SSO are automatically created. Their Open WebUI role
is set based on `OAUTH_ADMIN_ROLES` — users with `ai-admin` get admin access,
all others get standard user access.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags openwebui
```
