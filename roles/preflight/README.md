# Role: preflight

## Purpose

Pre-flight validation that runs before any changes are made to the infrastructure.
Ensures all hosts are reachable, have sufficient resources, and that critical
services are in an expected state.

## What It Checks

| Check             | Hosts            | Condition                                      |
|-------------------|------------------|------------------------------------------------|
| SSH access        | All 3 hosts      | Can connect via SSH                            |
| sudo access       | All 3 hosts      | Can escalate to root                           |
| Disk space (data) | ai_server        | `/mnt/ai_data` has >= 500 GB free              |
| Disk space (root) | coredns_host     | `/` has >= 10 GB free                          |
| Ollama API health | ai_server        | `curl localhost:11434` returns HTTP 200         |

## Requirements

- Valid Ansible inventory with all 3 hosts configured
- SSH key auth or password auth configured for the target user

## Failure Modes

Every check produces a clear failure message that includes:

- **Host** -- which host failed the check
- **Check** -- what was being validated
- **Expected** -- the passing condition
- **Actual** -- what was found

Example:

```
FAILED: Host ai_server, Check: disk_space(/mnt/ai_data),
        Expected: >= 500GB free, Actual: 312GB free
```

The playbook halts immediately on any preflight failure. No changes are made to any
host until all preflight checks pass.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags preflight
```
