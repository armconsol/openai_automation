# Role: openwebui

## Purpose

Deploy Open WebUI with full Ollama integration across both NUMA instances, RAG support
via Qdrant, and SSO via Keycloak OIDC.

## Ollama Backend Configuration

Open WebUI connects to **both** Ollama instances simultaneously via `OLLAMA_BASE_URLS`.
It load-balances requests across them and presents models from both as a single unified
list.

| Instance      | Port  | Models              |
|---------------|-------|---------------------|
| Node 1        | 11434 | General (slots 1-2-5) |
| Node 0        | 11435 | Coding (slots 3-4-6) |

## Environment Variables

| Variable                      | Value                                                                                     | Source      |
|-------------------------------|-------------------------------------------------------------------------------------------|-------------|
| `OLLAMA_BASE_URLS`            | `http://host.docker.internal:11434;http://host.docker.internal:11435`                    | Hardcoded   |
| `OLLAMA_API_KEY`              | (Ollama API key)                                                                          | Vault       |
| `RAG_OLLAMA_BASE_URL`         | `http://host.docker.internal:11434`                                                       | Hardcoded   |
| `WEBUI_SECRET_KEY`            | (session signing key)                                                                     | Vault       |
| `VECTOR_DB`                   | `qdrant`                                                                                  | Hardcoded   |
| `QDRANT_URI`                  | `http://host.docker.internal:6333`                                                        | Hardcoded   |
| `OAUTH_CLIENT_ID`             | `open-webui`                                                                              | Hardcoded   |
| `OAUTH_CLIENT_SECRET`         | (OIDC client secret)                                                                      | Vault       |
| `OPENID_PROVIDER_URL`         | `https://idm.<domain>/realms/<keycloak_realm>/.well-known/openid-configuration`           | Vault       |
| `OAUTH_PROVIDER_NAME`         | `{{ platform_name }}`                                                                     | group_vars  |
| `ENABLE_OAUTH_SIGNUP`         | `true`                                                                                    | Hardcoded   |
| `ENABLE_OAUTH_ROLE_MANAGEMENT`| `true`                                                                                    | Hardcoded   |
| `OAUTH_ROLES_CLAIM`           | `realm_access.roles`                                                                      | Hardcoded   |
| `OAUTH_ALLOWED_ROLES`         | `ai-user,ai-admin`                                                                        | Hardcoded   |
| `OAUTH_ADMIN_ROLES`           | `ai-admin`                                                                                | Hardcoded   |
| `DEFAULT_MODELS`              | `llama-family`                                                                            | Hardcoded   |
| `WEBUI_NAME`                  | `{{ platform_name }}`                                                                     | group_vars  |

## OIDC Setup

Open WebUI uses Keycloak as its OIDC provider:

1. `OAUTH_CLIENT_ID` is set to `open-webui` (matching the Keycloak client)
2. `OAUTH_CLIENT_SECRET` is read from Vault at `{{ vault_secret_prefix }}/keycloak:client_secret`
3. `OPENID_PROVIDER_URL` points to the Keycloak OIDC discovery endpoint

## RAG

- **Vector DB:** Qdrant at `http://host.docker.internal:6333`
- `RAG_OLLAMA_BASE_URL` is pinned to port 11434 (Node 1) for embedding requests —
  keeping RAG on a single stable endpoint avoids split-brain embedding indices
- Users can upload documents through the Open WebUI interface for RAG-augmented conversations

## SSO

Access is restricted by Keycloak realm role:

| Keycloak role | Open WebUI access      |
|---------------|------------------------|
| `ai-user`     | ✅ Standard user       |
| `ai-admin`    | ✅ Admin               |
| *(none)*      | ❌ Login blocked       |

## Tags

```bash
ansible-playbook playbooks/site.yml --tags openwebui -K -e @local.yml
```
