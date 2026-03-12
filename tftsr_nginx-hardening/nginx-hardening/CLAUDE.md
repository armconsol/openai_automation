# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Target Environment

- **OS:** RHEL 9, **NGINX:** 1.20+ at `/etc/nginx/`
- Playbooks target `hosts: all` — configure the target in `inventory/hosts.yml`
- `sudo dnf install -y ansible-core` is required on the control node before first run

## Run Commands

```bash
# Full hardening (all three roles)
ansible-playbook -K site.yml

# Individual roles
ansible-playbook -K playbooks/nginx_hardening.yml
ansible-playbook -K playbooks/fail2ban.yml
ansible-playbook -K playbooks/geo_blocking.yml

# Refresh country IP ranges from ipdeny.com (run periodically)
ansible-playbook -K playbooks/update_geo_blocks.yml

# Dry run — no changes applied
ansible-playbook -K --check site.yml
```

## Architecture

Three independent roles, each runnable standalone via `playbooks/`:

### `nginx_hardening`
Deploys four files to `/etc/nginx/conf.d/` prefixed `00-` so they sort before all service configs:
- `00-security-headers.conf` — `server_tokens off`, HSTS, X-Frame-Options, rate-limit zone, client body size
- `00-ssl-params.conf` — TLS 1.2/1.3 only, cipher suite, OCSP stapling, resolver
- `00-proxy-params.conf` — strips `X-Powered-By`/`Server`, sets `X-Real-IP`/`X-Forwarded-*` headers
- `00-http-redirects.conf` — port-80 301 redirect server blocks for the 11 services that lack them

**Critical constraint:** Existing service configs in `/etc/nginx/conf.d/` are never modified. Only list services in `nginx_redirect_services` that are **missing** a port-80 redirect — services that already have one must be excluded or NGINX will have duplicate `server_name` entries. Do not add `ssl_session_cache` to `00-ssl-params.conf` — if any existing service configs already declare `shared:SSL:Xm` in their server blocks, a conflicting http-level declaration with a different size will break `nginx -t`.

### `fail2ban`
Installs fail2ban from EPEL, deploys filter definitions and `jail.local`. Three jails:
- `sshd` → `/var/log/secure`
- `nginx-4xx` → `/var/log/nginx/access.log` (regex: any 4xx)
- `nginx-auth` → `/var/log/nginx/access.log` (regex: 401/403 only)

### `geo_blocking`
Downloads per-country CIDR files from `ipdeny.com/ipblocks/data/aggregated/{cc}-aggregated.zone` at runtime, assembles them into a single nftables set, and loads a standalone `table inet geo_block` (does not touch any existing nftables rules). The include line is appended to `/etc/sysconfig/nftables.conf`. Downloads use `ignore_errors: yes` — missing zone files are silently skipped.

**To unblock a country:** set `blocked: false` for its entry in `roles/geo_blocking/defaults/main.yml` and re-run `update_geo_blocks.yml`.

**ipdeny-absent territories** (no zone file exists — permanently `blocked: false`, no IPs to block): BV, CX, EH, GS, HM, PN, SH, SJ, TF, XK.

**DMZ host has no outbound internet** — zone files must be pre-downloaded elsewhere and copied over:
```bash
# On a machine WITH internet access:
./scripts/download-geo-zones.sh /tmp/geo_zones
rsync -av --no-group /tmp/geo_zones/ user@your-host:/opt/geo_zones/

# Then run with the local cache:
ansible-playbook -K playbooks/geo_blocking.yml -e geo_zone_files_dir=/opt/geo_zones
```
The role does a fast 8-second HEAD check to ipdeny.com first; if it fails and `geo_zone_files_dir` is unset, the play fails immediately rather than timing out on all 238 countries.

**YAML boolean trap:** `code: NO` (Norway) is parsed as boolean `false` by PyYAML (YAML 1.1). It must stay quoted as `code: "NO"`. Watch for this if adding new entries.

## Key Design Decisions

- All `template`/`copy`/`lineinfile` tasks use `backup: yes` — timestamped backups are created automatically on every run alongside the modified file.
- The nft template opens with `add table inet geo_block` + `flush table inet geo_block` for idempotency (safe to re-run).
- The `geo_blocking` role downloads zone files to a `tempfile` directory and cleans it up at the end of every run.
- Handlers fire only when a task reports `changed` — NGINX reload and fail2ban restart are not triggered on idempotent re-runs.
