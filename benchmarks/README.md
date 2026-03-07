# Benchmarks

## Overview

Dynamic benchmark system for all installed Ollama models. Runs a suite of coding and
general-purpose tests against every model currently available on the Ollama server,
scores each model on a composite metric, and assigns models to the 4-slot system
based on results.

## How to Run

**Benchmark all installed models:**

```bash
ansible-playbook playbooks/05_benchmark.yml
```

**Benchmark specific models only:**

```bash
ansible-playbook playbooks/05_benchmark.yml -e '{"benchmark_specific_models":["qwen2.5-coder:14b","deepseek-coder-v2:16b"]}'
```

**Benchmark with automatic model pulling if a better model is found:**

```bash
ansible-playbook playbooks/05_benchmark.yml -e pull_if_better=true
```

## Test Suites

### Coding Tests

| Test       | Prompt                                                         | What Is Measured              |
|------------|----------------------------------------------------------------|-------------------------------|
| `code_gen` | "Write a Python function that implements binary search on a sorted list. Include type hints and docstring." | Correctness (def + return present), code structure, tokens/sec |
| `debug`    | "Find and fix the bug in this Python code: `def factorial(n): return n * factorial(n)`. Explain the issue." | Identifies base case bug, explanation quality, tokens/sec |
| `refactor` | "Refactor this code to use list comprehension: `result = []; for i in range(10): if i % 2 == 0: result.append(i*i)`" | Produces list comprehension, conciseness, tokens/sec |

### General Tests

| Test        | Prompt                                                        | What Is Measured              |
|-------------|---------------------------------------------------------------|-------------------------------|
| `explain`   | "Explain the concept of recursion to a beginner programmer. Use a simple analogy." | Clarity, analogy presence, length adequacy, tokens/sec |
| `creative`  | "Write a short poem about artificial intelligence."           | Creativity (line count, poetic structure), tokens/sec |
| `reasoning` | "A farmer has 17 sheep. All but 9 die. How many are left? Explain your reasoning step by step." | Correct answer (9), step-by-step reasoning, tokens/sec |

### Latency Test

| Test      | Prompt | What Is Measured           |
|-----------|--------|----------------------------|
| `latency` | "Hi"   | Time to first token (TTFT) |

## Scoring

### Metrics Collected from Ollama API

- **tokens/sec** -- generation throughput from `/api/generate` response
- **TTFT** (time to first token) -- measured from request start to first streamed token
- **Quality heuristics** -- regex and length checks specific to each test type

### Composite Score Formula

For each category (coding, general), a composite score is calculated:

```
composite = (quality * 0.45) + (tokens_per_sec_normalized * 0.30) + (latency_score * 0.25)
```

Where:
- `quality` is 0.0-1.0 based on heuristic checks for the test type
- `tokens_per_sec_normalized` is the model's tokens/sec divided by the fastest model's tokens/sec
- `latency_score` is 1.0 - (model_ttft / slowest_ttft)

### Classification Rule

A model is classified as a **coding** model if:

```
coding_composite - general_composite >= 0.15
```

Otherwise it is classified as **general**.

## Thresholds and Configuration

All thresholds are configurable via `group_vars/all.yml`:

| Key                            | Default | Description                                    |
|--------------------------------|---------|------------------------------------------------|
| `benchmark_min_tokens_per_sec` | 10      | Minimum tokens/sec to pass a model             |
| `benchmark_max_ttft_ms`        | 5000    | Maximum time to first token in milliseconds    |
| `benchmark_quality_weight`     | 0.45    | Weight of quality score in composite            |
| `benchmark_speed_weight`       | 0.30    | Weight of tokens/sec in composite               |
| `benchmark_latency_weight`     | 0.25    | Weight of latency score in composite            |
| `benchmark_coding_threshold`   | 0.15    | Minimum coding-general delta for coding classification |

## Output Format

### Benchmark Report

Each run produces `benchmarks/benchmark_<timestamp>.md` with a results table:

```
| Model                  | Coding Composite | General Composite | Classification | Tokens/sec | TTFT (ms) |
|------------------------|------------------|-------------------|----------------|------------|-----------|
| qwen2.5-coder:14b      | 0.82             | 0.65              | coding         | 38.2       | 420       |
| deepseek-coder-v2:16b  | 0.78             | 0.63              | coding         | 35.1       | 510       |
| llama3.1:8b            | 0.61             | 0.74              | general        | 52.3       | 280       |
| mistral:7b             | 0.58             | 0.71              | general        | 55.8       | 250       |
```

### Model Selection File

Results are also written to `model_selection.json`:

```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "slot1_coding": "qwen2.5-coder:14b",
  "slot2_general": "llama3.1:8b",
  "slot3_backup": "deepseek-coder-v2:16b",
  "slot4_experimental": null,
  "results": { ... }
}
```

## Slot Selection

Slots are assigned from benchmark results as follows:

1. **Slot 1 (Primary Coding)** -- model with the highest `coding_composite` score
2. **Slot 2 (Primary General)** -- model with the highest `general_composite` score
3. **Slot 3 (Secondary / Backup)** -- next-best model by overall average composite
4. **Slot 4 (Experimental)** -- not assigned by benchmarks; set manually via `-e slot4_model=<name>`
