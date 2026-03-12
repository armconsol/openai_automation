# Role: models

## Purpose

Manage the Ollama model lifecycle — pulling models, creating custom Modelfile
configurations, and running warm-up services to ensure models are loaded into RAM
at boot time across both NUMA instances.

## 6-Slot System

| Slot | Instance      | Port  | Role             | Selection                      | Rotation                    |
|------|---------------|-------|------------------|--------------------------------|-----------------------------|
| 1    | Node 1        | 11434 | General (locked) | Top general composite          | Re-benchmark only           |
| 2    | Node 1        | 11434 | General (locked) | 2nd general composite          | Re-benchmark only           |
| 5    | Node 1        | 11434 | General (rotate) | 3rd general composite          | `-e slot5_model=<name>`     |
| 3    | Node 0        | 11435 | Coding (locked)  | Top coding composite           | Re-benchmark only           |
| 4    | Node 0        | 11435 | Coding (locked)  | 2nd coding composite           | Re-benchmark only           |
| 6    | Node 0        | 11435 | Coding (rotate)  | 3rd coding composite           | `-e slot6_model=<name>`     |

## Slot Rotation

Rotate the general slot on Node 1 (port 11434):

```bash
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot5_model=mistral:latest"
```

Rotate the coding slot on Node 0 (port 11435):

```bash
ansible-playbook playbooks/04_models.yml -K -e @local.yml -e "slot6_model=llama3.1:70b"
```

Both at once:

```bash
ansible-playbook playbooks/04_models.yml -K -e @local.yml \
  -e "slot5_model=mistral:latest" -e "slot6_model=command-r:35b"
```

Reset both rotate slots back to benchmark recommendations:

```bash
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

## Modelfile Configurations

Custom Modelfile variants are created for fine-tuned context windows:

| Custom Model    | Base Slot    | Context | Port  | Use Case                         |
|-----------------|--------------|---------|-------|----------------------------------|
| `coder-128k`    | slot3_coding | 32768   | 11435 | Primary coding (large context)   |
| `coder-32k`     | slot4_coding | 32768   | 11435 | Secondary coding                 |
| `coder-rotate`  | slot6_coding_rotate | 32768 | 11435 | Rotatable coding model      |
| `llama-family`  | llama3.2:3b  | 8192    | 11434 | Family-safe general assistant    |
| `gemma-family`  | llama3.1:8b  | 8192    | 11434 | Family-safe general assistant    |

**These aliases are excluded from benchmarking** via `benchmark_skip_aliases` — their
32k-token parameter allocations stall the benchmark loop with 285-second responses.

## Warm-up Services

Two oneshot systemd services pre-load models after their respective Ollama instances start:

| Service                      | Warms               | Instance            |
|------------------------------|---------------------|---------------------|
| `ollama-warmup.service`      | slots 1, 2, 5       | Node 1 (port 11434) |
| `ollama-warmup-node0.service`| slots 3, 4, 6       | Node 0 (port 11435) |

`OLLAMA_KEEP_ALIVE=-1` keeps models pinned once loaded. The warmup services only
need to run once after boot; subsequent requests hit already-loaded models immediately.

Check warmup status:

```bash
systemctl status ollama-warmup ollama-warmup-node0
```

Re-run warmup manually (e.g. after rotating a slot):

```bash
systemctl restart ollama-warmup          # Node 1 general models
systemctl restart ollama-warmup-node0    # Node 0 coding models
```

## model_selection.json

`playbooks/04_models.yml` reads `benchmarks/results/model_selection.json`:

```json
{
  "slot1_general": "llama3.1:8b",
  "slot2_general": "mistral:latest",
  "slot5_general_rotate": "llama3.2:3b",
  "slot3_coding": "deepseek-coder-v2:16b",
  "slot4_coding": "qwen2.5-coder:7b",
  "slot6_coding_rotate": "codegemma:7b",
  "general_ranking": [...],
  "coding_ranking": [...],
  "all_metrics": { ... }
}
```

## Tags

```bash
ansible-playbook playbooks/site.yml --tags models -K -e @local.yml
ansible-playbook playbooks/site.yml --tags models-warmup -K -e @local.yml
```
