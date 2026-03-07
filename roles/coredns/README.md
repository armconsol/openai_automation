# Role: coredns

## Purpose

Add DNS records for new services to the CoreDNS zone file on `coredns_host` (`coredns_host_ip`).

## Zone File

```
/docker_mounts/coredns/<domain>.db
```

This file is the authoritative zone file for `{{ domain }}` served by the CoreDNS
Docker container on the coredns_host.

## Records Managed

| Record                       | Type | Value               |
|------------------------------|------|---------------------|
| `vault.<domain>`             | A    | `<nginx_proxy_ip>`  |
| `ollama-api.<domain>`        | A    | `<nginx_proxy_ip>`  |

All service DNS records point to the NGINX proxy (`nginx_proxy_ip`), which handles
TLS termination and reverse proxying to the actual service backends.

## Entry Format

Each DNS record follows this format:

```
<name>.<domain>.  3600  IN  A  <nginx_proxy_ip>
```

Example (with defaults `domain=example.com`, `nginx_proxy_ip=192.168.1.30`):

```
vault.example.com.      3600  IN  A  192.168.1.30
ollama-api.example.com. 3600  IN  A  192.168.1.30
```

## Reload

After modifying the zone file, CoreDNS is reloaded by sending SIGHUP to the
container:

```bash
docker kill --signal=SIGHUP coredns
```

## Idempotency

The role uses Ansible's `lineinfile` module to add DNS records. This ensures:

- Records are added only if they do not already exist
- Existing records are not duplicated
- Other records in the zone file are not affected

## Tags

```bash
ansible-playbook playbooks/site.yml --tags coredns
```
