# Role: benchmark

## Purpose

Benchmark all installed Ollama models to determine optimal slot assignments. Runs
coding and general-purpose test suites, scores each model, and writes results to
the benchmark report and `model_selection.json`.

## Test Details

| Test        | Category | Prompt                                                                                          | Scoring Method            |
|-------------|----------|-------------------------------------------------------------------------------------------------|---------------------------|
| `code_gen`  | coding   | "Write a Python function that implements binary search on a sorted list. Include type hints and docstring." | `def` + `return` present, code structure |
| `debug`     | coding   | "Find and fix the bug: `def factorial(n): return n * factorial(n)`. Explain the issue."          | Base case identified, explanation quality |
| `refactor`  | coding   | "Refactor to list comprehension: `result = []; for i in range(10): if i % 2 == 0: result.append(i*i)`" | List comprehension present, conciseness |
| `explain`   | general  | "Explain recursion to a beginner programmer. Use a simple analogy."                              | Clarity, analogy present, length adequate |
| `creative`  | general  | "Write a short poem about artificial intelligence."                                              | Line count, poetic structure |
| `reasoning` | general  | "A farmer has 17 sheep. All but 9 die. How many are left? Explain step by step."                 | Correct answer (9), reasoning steps |
| `latency`   | latency  | "Hi"                                                                                             | Time to first token (TTFT) |

## Quality Heuristics

Each test type uses specific checks to score quality (0.0 to 1.0):

- **code_gen** -- regex checks for `def `, `return`, type hint patterns (`: `), docstring (`"""`); score based on how many are present
- **debug** -- checks for mention of base case, `if n <= 1` or similar fix, explanation length
- **refactor** -- checks for `[` list comprehension syntax, absence of `for`/`append` loop pattern, output length relative to input
- **explain** -- checks response length (>100 chars), presence of analogy keywords ("like", "imagine", "similar"), paragraph count
- **creative** -- checks line count (>=4), presence of line breaks, absence of purely prose output
- **reasoning** -- checks for "9" in response, presence of step indicators ("step", "first", "because", numbered lists)

## Scoring Formula

```
composite = (quality * 0.45) + (tokens_per_sec_normalized * 0.30) + (latency_score * 0.25)
```

### Example Calculation

For a model with quality=0.8, tokens/sec=38.2 (fastest=55.8), TTFT=420ms (slowest=510ms):

```
tokens_per_sec_normalized = 38.2 / 55.8 = 0.685
latency_score = 1.0 - (420 / 510) = 0.176

composite = (0.8 * 0.45) + (0.685 * 0.30) + (0.176 * 0.25)
          = 0.360 + 0.206 + 0.044
          = 0.610
```

## Configuration

All parameters are configurable via `group_vars/all.yml`:

| Key                            | Default | Description                                    |
|--------------------------------|---------|------------------------------------------------|
| `benchmark_min_tokens_per_sec` | 10      | Minimum tokens/sec to pass a model             |
| `benchmark_max_ttft_ms`        | 5000    | Maximum acceptable time to first token (ms)    |
| `benchmark_quality_weight`     | 0.45    | Weight of quality score in composite            |
| `benchmark_speed_weight`       | 0.30    | Weight of normalized tokens/sec in composite    |
| `benchmark_latency_weight`     | 0.25    | Weight of latency score in composite            |
| `benchmark_coding_threshold`   | 0.15    | Min coding-general delta for coding classification |

## Candidate Models

| Model                   | Size  | Expected Speed | Reasoning                              |
|-------------------------|-------|----------------|----------------------------------------|
| `qwen2.5-coder:14b`    | 14B   | ~35-40 tok/s   | Strong coding performance at moderate size |
| `deepseek-coder-v2:16b`| 16B   | ~30-38 tok/s   | Competitive coding with broad language support |
| `llama3.1:8b`          | 8B    | ~50-55 tok/s   | Fast general-purpose model             |
| `mistral:7b`           | 7B    | ~50-58 tok/s   | Fast general-purpose, good reasoning   |

## Output Files

### Benchmark Report

Written to `benchmarks/benchmark_<timestamp>.md`:

```
| Model                  | Coding Composite | General Composite | Classification | Tokens/sec | TTFT (ms) |
|------------------------|------------------|-------------------|----------------|------------|-----------|
| qwen2.5-coder:14b      | 0.82             | 0.65              | coding         | 38.2       | 420       |
| ...                    | ...              | ...               | ...            | ...        | ...       |
```

### Model Selection

Written to `model_selection.json`:

```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "slot1_coding": "qwen2.5-coder:14b",
  "slot2_general": "llama3.1:8b",
  "slot3_backup": "deepseek-coder-v2:16b",
  "slot4_experimental": null,
  "results": {
    "qwen2.5-coder:14b": {
      "coding_composite": 0.82,
      "general_composite": 0.65,
      "classification": "coding",
      "tokens_per_sec": 38.2,
      "ttft_ms": 420
    }
  }
}
```

## Tags

```bash
ansible-playbook playbooks/site.yml --tags benchmark
```
