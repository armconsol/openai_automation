# Role: docker

## Purpose

Install Docker CE on target hosts that require container runtime.

## Installation

Docker CE is installed via `dnf` using the official Docker CE repository. The role:

1. Adds the Docker CE dnf repository
2. Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, and `docker-compose-plugin`
3. Enables and starts the `docker` service

## Group Membership

The following users are added to the `docker` group:

- `{{ ansible_user }}` -- primary admin user (set via `ansible_user` in `group_vars/all.yml`)
- `ollama` -- Ollama service user

A logout/login is required for group membership changes to take effect in existing
shell sessions.

## Idempotency

- Skips installation if the `docker` binary is already present and the `docker`
  service is running
- Group membership is additive (does not remove existing groups)

## Tags

```bash
ansible-playbook playbooks/site.yml --tags docker
```
