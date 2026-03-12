# Role: ollama

## Purpose

Install, configure, and maintain Ollama inference server(s) on the AI server host.
Two instances run simultaneously — one per NUMA socket — to utilize both CPU sockets
on the Dell M630 (2× E5-2690v4).

## Instances

| Service                | Port  | NUMA Node | CPUs (physical only) | RAM binding | Purpose          |
|------------------------|-------|-----------|----------------------|-------------|------------------|
| `ollama.service`       | 11434 | Node 1    | 1 3 5 … 27 (odd)     | `--membind=1` | General models |
| `ollama-node0.service` | 11435 | Node 0    | 0 2 4 … 26 (even)    | `--membind=0` | Coding models  |

Both instances share the same model storage directory (`/mnt/ai_data/ollama_models`)
and Ollama API key. Weights are loaded once into the NUMA node's memory; they are not
duplicated between instances.

## Configuration

### Node 1 — systemd override

Applied via `/etc/systemd/system/ollama.service.d/override.conf` (templated from
`templates/ollama/override.conf.j2`):

| Variable                   | Value                        | Description                                      |
|----------------------------|------------------------------|--------------------------------------------------|
| `OLLAMA_API_KEY`           | (from Vault)                 | Shared key for all API requests                  |
| `OLLAMA_HOST`              | `0.0.0.0:11434`              | Listen on all interfaces, port 11434             |
| `OLLAMA_MODELS`            | `/mnt/ai_data/ollama_models` | Shared model storage                             |
| `OLLAMA_KEEP_ALIVE`        | `-1`                         | Never unload models from RAM                     |
| `OLLAMA_FLASH_ATTENTION`   | `1`                          | Fused softmax — ~20% less memory bandwidth       |
| `OLLAMA_NUM_THREADS`       | `14`                         | Physical cores on NUMA node 1 only               |
| `OLLAMA_NUM_PARALLEL`      | `2`                          | Concurrent inference streams per instance        |
| `OLLAMA_MAX_LOADED_MODELS` | `3`                          | 3 models warm per instance (6 total)             |
| `CPUAffinity`              | `1 3 5 … 27`                 | Odd CPUs = socket 1 physical cores               |
| `ExecStart`                | `numactl --membind=1 ollama serve` | Pin memory allocations to Node 1 RAM        |

### Node 0 — standalone systemd unit

Deployed to `/etc/systemd/system/ollama-node0.service` (from
`templates/ollama/ollama-node0.service.j2`). Uses the same variables but with:

| Variable   | Value           |
|------------|-----------------|
| `OLLAMA_HOST` | `0.0.0.0:11435` |
| `CPUAffinity` | `0 2 4 … 26` |
| `ExecStart`   | `numactl --membind=0 ollama serve` |

## NUMA Rationale

On the M630 with dual E5-2690v4:
- **Node 1** (odd CPUs) has ~120 GB free RAM — assigned general models (larger)
- **Node 0** (even CPUs) has ~75 GB free RAM — assigned coding models

Without `numactl --membind`, the OS allocates model weights and KV cache across both
nodes, causing cross-socket memory traffic (~40 GB/s vs ~68–75 GB/s local).
`CPUAffinity` alone sets the scheduler; `numactl` sets the memory policy.

## OLLAMA_FLASH_ATTENTION

Enables fused softmax kernel — reduces attention memory bandwidth by ~20% and improves
throughput at all context lengths on AVX2 (E5-2690v4). Note: `OLLAMA_KV_CACHE_TYPE`
is intentionally **not** set — q8_0 dequantization overhead regressed throughput on
this CPU despite the bandwidth savings.

## Upgrade Procedure

```bash
ansible-playbook playbooks/02_infrastructure.yml -K -e @local.yml --tags ollama
```

The official install script detects the existing installation and performs an in-place
upgrade. Both `ollama.service` and `ollama-node0.service` are restarted.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags ollama -K -e @local.yml
```
