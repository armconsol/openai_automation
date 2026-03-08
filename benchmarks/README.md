# Benchmarks

## Overview

Dynamic benchmark system for all installed Ollama models. Runs a suite of coding and
general-purpose tests against every model on the Ollama server, scores each model on a
composite metric, and assigns models to the 6-slot dual-socket system based on results.

Modelfile aliases (`coder-128k`, `coder-32k`, `coder-rotate`, `llama-family`,
`gemma-family`) are automatically excluded from benchmarking — they share weights with
real models and their large context window parameters would stall every run with
285-second KV-cache allocations.

## How to Run

**Benchmark all installed models:**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml
```

**Benchmark specific models only:**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_models=qwen2.5-coder:14b,deepseek-coder-v2:16b"
```

**Benchmark and immediately push 6-slot warm-up selections:**

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml && \
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

## Three-Pass Execution

Models are split into three size tiers before benchmarking. Each tier gets its own
per-request timeout to avoid small models waiting behind 70 B giants:

| Tier   | RAM threshold | Timeout | Description                       |
|--------|---------------|---------|-----------------------------------|
| Small  | < 10 GB       | 300 s   | 7 B and under — fast path         |
| Medium | 10–15 GB      | 900 s   | 16 B lite / 12 B — standard wait  |
| Large  | > 15 GB       | 1200 s  | 34 B+ — 20-minute ceiling         |

**Size source vs runtime RAM:** `ollama list` reports on-disk (compressed) sizes, which
are smaller than actual runtime RAM usage (model weights + KV cache + overhead). A
`benchmark_size_overhead_factor` (default `1.2`) is applied when computing tier
boundaries: the disk-size cutoffs are divided by the factor before comparison. For
example, with default settings a 9 GB on-disk model is treated as ~10.8 GB at runtime
and falls in the medium tier rather than small.

**Override tier boundaries:**

```bash
# Adjust where small/medium boundary sits
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_small_max_gb=8 benchmark_medium_max_gb=20"

# Tune the overhead factor if your models load larger/smaller than expected
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_size_overhead_factor=1.25"

# Override timeouts only
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_medium_timeout=600 benchmark_large_timeout=1800"
```

## Test Suites

### Coding Tests

| Test       | Prompt                                                                     | What Is Measured                                   |
|------------|----------------------------------------------------------------------------|----------------------------------------------------|
| `code_gen` | Write a Python merge sort with type hints, docstring, and 3 unit tests     | `def`, `return`, `"""`, `->`, `assert`, `def test_`, `import` |
| `debug`    | Find and fix 3 bugs in a given Python function                             | `def`, `return`, code block, `assert`              |
| `refactor` | Refactor a loop for readability and performance                            | `def`, `return`, code block, type hint, `import`   |

### General Tests

| Test        | Prompt                                                     | What Is Measured                                     |
|-------------|------------------------------------------------------------|------------------------------------------------------|
| `explain`   | Explain how Python's GIL works and when it matters         | Response length, paragraph structure, list formatting |
| `creative`  | Suggest 5 fun family activities for a rainy weekend        | Response length, paragraph structure, list formatting |
| `reasoning` | Apple arithmetic word problem                              | Response length, paragraph structure, list formatting |

### Latency Test

| Test      | Prompt | What Is Measured                                   |
|-----------|--------|----------------------------------------------------|
| `latency` | "Hi"   | Total response time (eval + prompt eval), used as TTFT proxy |

## Scoring

### Composite Score Formula

For each category (coding, general), a composite score is calculated:

```
composite = (quality * 0.45) + (tokens_per_sec / ceiling, capped 1.0) * 0.30
          + (1 - ttft_ms / 5000, floored 0) * 0.25
```

Where:
- `quality` — 0.0–1.0 from heuristic checks per test type (see CLAUDE.md for weights)
- `tokens_per_sec` — averaged across all test responses; normalized against `benchmark_toks_norm_ceiling` (default 40)
- `ttft_ms` — latency test response time in milliseconds

### Classification Rule

A model is classified as **coding** if:

```
coding_composite - general_composite >= benchmark_coding_threshold   # default 0.10
```

Name-pattern heuristics (`coder`, `codestral`, `codellama`, `starcoder`) apply as a
tiebreaker. Category can also be forced with `model_category_overrides` in `group_vars/all.yml`.

## Thresholds and Configuration

All thresholds are configurable in `inventory/group_vars/all.yml`:

| Key                               | Default | Description                                            |
|-----------------------------------|---------|--------------------------------------------------------|
| `benchmark_thresholds.min_tokens_per_sec`  | 5.0  | Minimum tok/sec to be slot-eligible          |
| `benchmark_thresholds.min_quality_score`   | 0.6  | Minimum quality score to be slot-eligible    |
| `benchmark_thresholds.min_composite_score` | 0.55 | Minimum composite to avoid threshold warning |
| `benchmark_toks_norm_ceiling`     | 40      | tok/sec ceiling for normalization (dual-socket target) |
| `benchmark_coding_threshold`      | 0.10    | coding-general composite delta for classification      |
| `benchmark_small_max_gb`          | 10      | Runtime RAM upper bound for small pass (GB)            |
| `benchmark_medium_max_gb`         | 15      | Runtime RAM upper bound for medium pass (GB)           |
| `benchmark_size_overhead_factor`  | 1.2     | Multiplier applied to `ollama list` disk sizes to estimate runtime RAM |
| `benchmark_small_timeout`         | 300     | Per-request timeout for small models (seconds)         |
| `benchmark_medium_timeout`        | 900     | Per-request timeout for medium models (seconds)        |
| `benchmark_large_timeout`         | 1200    | Per-request timeout for large models (seconds)         |
| `benchmark_skip_aliases`          | see below| Modelfile aliases excluded from benchmark loop        |

Default `benchmark_skip_aliases`:
```yaml
- coder-128k
- coder-32k
- coder-rotate
- llama-family
- gemma-family
```

## Output Format

### Benchmark Report

Each run produces `benchmarks/results/benchmark_<timestamp>.md`. The slot table now
covers all 6 slots across both NUMA instances:

```
| Slot | Socket              | Role            | Model                     | Composite |
|------|---------------------|-----------------|---------------------------|-----------|
| 1    | Node 1 (port 11434) | General (locked)| llama3.1:8b               | 0.74      |
| 2    | Node 1 (port 11434) | General (locked)| mistral:latest            | 0.71      |
| 5    | Node 1 (port 11434) | General (rotate)| llama3.2:3b               | 0.63      |
| 3    | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:16b     | 0.82      |
| 4    | Node 0 (port 11435) | Coding (locked) | qwen2.5-coder:7b          | 0.78      |
| 6    | Node 0 (port 11435) | Coding (rotate) | codegemma:7b              | 0.69      |
```

### model_selection.json

Results are written to `benchmarks/results/model_selection.json`:

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

This file is read by `04_models.yml` to decide what to pull and warm up. It is committed
to the repo so slot selections survive a clean checkout.
