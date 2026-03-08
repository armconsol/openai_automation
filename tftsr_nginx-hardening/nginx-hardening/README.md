# nginx-hardening

Ansible project to harden an NGINX reverse proxy to a production security posture. Applies security headers, TLS hardening, HTTP→HTTPS redirects, fail2ban jails, and nftables-based country geo-blocking — without modifying any existing service configurations.

## Target environment

- **OS:** RHEL 9 / Rocky Linux 9 / AlmaLinux 9
- **NGINX:** 1.20+ with existing service configs in `/etc/nginx/conf.d/`
- **EPEL:** Must be installed before running (`dnf install -y epel-release`)
- **nftables:** Installed but not required to be running (managed by this project)
- **firewalld:** Should be inactive to avoid nftables coexistence issues

## What it does

### Role: `nginx_hardening`
Deploys four files to `/etc/nginx/conf.d/` prefixed `00-` so they load before all service configs:

| File | Purpose |
|------|---------|
| `00-security-headers.conf` | `server_tokens off`, HSTS, X-Frame-Options, X-Content-Type-Options, CSP, rate-limit zone |
| `00-ssl-params.conf` | TLS 1.2/1.3 only, hardened cipher suite, OCSP stapling, session timeout |
| `00-proxy-params.conf` | Strips `X-Powered-By`/`Server`, sets `X-Real-IP` and `X-Forwarded-*` headers |
| `00-http-redirects.conf` | Port-80 → HTTPS 301 redirects for services listed in `nginx_redirect_services` |

**No existing service configs are modified.**

### Role: `fail2ban`
Installs fail2ban from EPEL and configures three jails:

| Jail | Log | Trigger |
|------|-----|---------|
| `sshd` | `/var/log/secure` | Failed SSH logins |
| `nginx-4xx` | `/var/log/nginx/access.log` | Repeated 4xx responses |
| `nginx-auth` | `/var/log/nginx/access.log` | Repeated 401/403 responses |

### Role: `geo_blocking`
Builds a standalone `table inet geo_block` nftables ruleset populated with CIDRs for every country except the US, downloaded from [ipdeny.com](https://www.ipdeny.com). The table is loaded at boot via `/etc/sysconfig/nftables.conf`.

## Prerequisites

On the **Ansible control node** (the machine you run `ansible-playbook` from):
```bash
# Ansible itself
pip install ansible-core
# or
dnf install -y ansible-core
```

On the **target host** (applied automatically by the playbooks):
- EPEL repo must already be installed
- SSH access with a user that can `sudo`

## Setup

### 1. Configure your inventory

Edit `inventory/hosts.yml`:
```yaml
all:
  hosts:
    nginx-proxy:
      ansible_host: 192.168.1.10          # your server's IP or hostname
      ansible_user: your_ssh_user
      # ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

### 2. Configure HTTP→HTTPS redirects

Edit `roles/nginx_hardening/defaults/main.yml` and populate `nginx_redirect_services` with any services that are **missing** a port-80 redirect in their existing NGINX config:

```yaml
nginx_redirect_services:
  - name: myapp
    server_name: myapp.example.com
  - name: dashboard
    server_name: dashboard.example.com
```

Services that already have a redirect in their existing `conf.d/` file should **not** be listed here.

### 3. (Optional) Tune defaults

All tunable variables live in each role's `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `nginx_hsts_max_age` | `31536000` | HSTS max-age in seconds |
| `nginx_rate_limit_req_zone` | `30r/m` | Rate limit zone definition |
| `nginx_client_max_body_size` | `10m` | Max upload body size |
| `fail2ban_bantime` | `3600` | Ban duration (seconds) |
| `fail2ban_maxretry_ssh` | `5` | SSH failures before ban |
| `fail2ban_maxretry_nginx_auth` | `5` | 401/403 failures before ban |

## Running

```bash
# Full hardening (all roles)
ansible-playbook -K site.yml

# Individual roles
ansible-playbook -K playbooks/nginx_hardening.yml
ansible-playbook -K playbooks/fail2ban.yml
ansible-playbook -K playbooks/geo_blocking.yml

# Refresh country IP ranges (run periodically — ipdeny.com updates regularly)
ansible-playbook -K playbooks/update_geo_blocks.yml

# Dry run — no changes applied
ansible-playbook -K --check site.yml
```

`-K` prompts for the sudo password. Omit it if your user has passwordless sudo.

## Geo-blocking: servers without direct internet access

If your target server cannot reach `ipdeny.com`, pre-download the zone files on a machine that can and copy them over:

```bash
# On a machine WITH unrestricted internet access:
./scripts/download-geo-zones.sh /tmp/geo_zones

# Copy to the target server:
rsync -av --no-group /tmp/geo_zones/ user@your-server:/opt/geo_zones/

# Run the playbook pointing at the local cache:
ansible-playbook -K playbooks/geo_blocking.yml -e geo_zone_files_dir=/opt/geo_zones
```

To make the cache path permanent, add it to your inventory:
```yaml
all:
  hosts:
    nginx-proxy:
      ansible_host: 192.168.1.10
      ansible_user: your_ssh_user
      geo_zone_files_dir: /opt/geo_zones
```

### Unblocking a country

Set `blocked: false` for the desired country code in `roles/geo_blocking/defaults/main.yml`, then re-run `update_geo_blocks.yml`.

## Verification

After a successful run:

```bash
# NGINX config is valid
sudo nginx -t

# Security headers are present
curl -sI https://your-domain.com | grep -i 'strict\|x-frame\|x-content'

# HTTP redirects to HTTPS
curl -I http://your-domain.com   # expect: 301 Moved Permanently

# fail2ban jails are active
sudo fail2ban-client status
sudo fail2ban-client status nginx-4xx

# nftables geo-block table is loaded
sudo nft list table inet geo_block
```

## Files written to the target host

| Path | Action |
|------|--------|
| `/etc/nginx/conf.d/00-security-headers.conf` | Created |
| `/etc/nginx/conf.d/00-ssl-params.conf` | Created |
| `/etc/nginx/conf.d/00-proxy-params.conf` | Created |
| `/etc/nginx/conf.d/00-http-redirects.conf` | Created |
| `/etc/fail2ban/jail.local` | Created |
| `/etc/fail2ban/filter.d/nginx-4xx.conf` | Created |
| `/etc/fail2ban/filter.d/nginx-auth.conf` | Created |
| `/etc/nftables.d/geo-block.nft` | Created |
| `/etc/sysconfig/nftables.conf` | Appended (include line) |

All tasks that write files use `backup: yes` — a timestamped copy is created automatically before each overwrite.
