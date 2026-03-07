# Role: models

## Purpose

Manage the Ollama model lifecycle -- pulling models, creating custom Modelfile
configurations, and running a warm-up service to ensure models are loaded into GPU
memory at boot time.

## Slot System

| Slot | Role               | Selection Method                         |
|------|--------------------|------------------------------------------|
| 1    | Primary Coding     | Highest coding composite from benchmarks |
| 2    | Primary General    | Highest general composite from benchmarks|
| 3    | Secondary / Backup | Next-best overall average composite      |
| 4    | Experimental       | Manual override via `-e slot4_model=<name>` |

## Slot Rotation

To override slot 4 with a specific model at runtime:

```bash
ansible-playbook playbooks/03_ollama.yml -e slot4_model=mistral:7b
```

Slots 1-3 are automatically assigned based on the latest benchmark results in
`model_selection.json`. Slot 4 is always user-controlled.

## Modelfile Configurations

Custom Modelfile variants are created for fine-tuned context windows and use cases:

| Custom Model          | Base Model           | Context Window | Use Case                    |
|-----------------------|----------------------|----------------|-----------------------------|
| `coding-primary`     | (slot 1 model)       | 32768          | Code generation and debugging |
| `general-primary`    | (slot 2 model)       | 16384          | General conversation and reasoning |
| `backup`             | (slot 3 model)       | 16384          | Fallback for either category |
| `experimental`       | (slot 4 model)       | 8192           | Testing new models           |

## Warm-up Service

The role deploys `ollama-warmup.service`, a oneshot systemd service that runs after
`ollama.service` starts.

**Why it is needed:** Even though `OLLAMA_KEEP_ALIVE=-1` keeps models loaded in GPU
memory indefinitely once loaded, Ollama does not automatically load models on
startup. The warm-up service sends a minimal inference request to each slot model,
triggering the initial load into GPU memory. Without this, the first user request
to each model would experience a long delay while the model is loaded.

The warm-up service:

1. Waits for Ollama API to be healthy
2. Sends a short prompt to each configured slot model
3. Exits after all models are loaded

## model_selection.json

The model selection file is read by this role to determine which models to assign to
each slot. Schema:

```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "slot1_coding": "qwen2.5-coder:14b",
  "slot2_general": "llama3.1:8b",
  "slot3_backup": "deepseek-coder-v2:16b",
  "slot4_experimental": null
}
```

If `model_selection.json` does not exist (first run before benchmarks), the role
falls back to default models defined in `group_vars/all.yml`.

## Tags

```bash
ansible-playbook playbooks/site.yml --tags models
ansible-playbook playbooks/site.yml --tags warmup
```
