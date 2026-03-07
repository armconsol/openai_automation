# Role: nginx

## Purpose

Manage NGINX reverse proxy configurations on `nginx_proxy` (`nginx_proxy_ip`) for all
platform services.

## Managed Configurations

| Config File              | Service    | Upstream Target                      |
|--------------------------|------------|--------------------------------------|
| `vault.conf`             | Vault      | `<ai_server_ip>:<vault_port>`        |
| `ollama-api.conf`        | Ollama API | `<ai_server_ip>:<ollama_port>`       |
| `keycloak-proxy.conf`    | Keycloak   | `<ai_server_ip>:<keycloak_port>`     |

Each configuration file is placed in `/etc/nginx/conf.d/` on the proxy host.

## SSL Certificates

TLS certificates for `*.<domain>` are stored at:

- **Certificate:** `/etc/nginx/ssl/<domain>.crt`
- **Private key:** `/etc/nginx/ssl/<domain>.key`

All reverse proxy configs reference these paths (via `nginx_ssl_cert` / `nginx_ssl_key` variables)
for TLS termination.

## How to Add a New Service

1. Create a new config file following the existing template pattern:

```nginx
upstream new_service {
    server {{ ai_server_ip }}:<target_port>;
}

server {
    listen 443 ssl;
    server_name new-service.{{ domain }};

    ssl_certificate     {{ nginx_ssl_cert }};
    ssl_certificate_key {{ nginx_ssl_key }};

    location / {
        proxy_pass http://new_service;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

2. Add the template to the role's `templates/` directory
3. Add the DNS record via the `coredns` role

## Configuration Validation

Before reloading NGINX, the role runs:

```bash
nginx -t
```

The reload is only performed if the configuration test passes. This prevents
broken configs from taking down the proxy.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags nginx
```
