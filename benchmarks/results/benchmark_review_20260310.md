# Ticket Summary — Post-Change Benchmark Review: num_predict 300 → 500

## Description

After resolving the dual NUMA/CPUAffinity performance regression (2026-03-10), two
post-fix benchmark runs were executed to validate the effect of raising
`benchmark_num_predict` from 300 to 500. This document captures the four-run history,
before/after comparison, full Run 4 model results, and findings on system tuning state.

---

## Acceptance Criteria

- [x] Run 3 (num_predict=300) and Run 4 (num_predict=500) compared on common models
- [x] All tuning variables reviewed and declared optimal or requiring action
- [x] Any model-identity anomalies flagged for follow-up
- [x] MEMORY.md updated with current variable values
- [x] This ticket summary written to `benchmarks/results/`

---

## Work Implemented

### Run History

| Run | Timestamp | Condition | Result |
|-----|-----------|-----------|--------|
| 1 | 20260309T080551 | Broken NUMA (membind + CPUAffinity) | quality=0, tok/sec≈0.0–0.1 |
| 2 | 20260309T174604 | Broken NUMA (same bug) | quality=0, tok/sec=0.1 |
| 3 | 20260310T094843 | Post-NUMA-fix, num_predict=300, 4 models | quality=0.78–0.97, tok/sec=6.5–22.8 |
| 4 | 20260310T110632 | Post-NUMA-fix, num_predict=500, 9 models | quality=0.83–0.97, tok/sec=3.2–25.0 |

### Before vs. After (Runs 3 → 4, common models)

| Model | coding_quality @ 300 | coding_quality @ 500 | Delta |
|-------|---------------------|---------------------|-------|
| deepseek-coder-v2:latest | 0.783 | 0.833 | +0.050 |
| qwen2.5-coder:7b | 0.800 | 0.850 | +0.050 |
| llama3.2:3b | 0.850 | 0.890 | +0.040 |
| gemma3:12b-it-q4_K_M | 0.850 | 0.873 | +0.023 |

### Full Run 4 Results (num_predict=500, 9 models)

| Model | tok/sec | coding_q | general_q | latency_ms | coding_composite | general_composite | category |
|-------|---------|----------|-----------|------------|-----------------|------------------|----------|
| deepseek-coder-v2:16b | 24.5 | 0.833 | 0.885 | 1415.1 | 0.738 | 0.762 | coding |
| deepseek-coder-v2:latest | 25.0 | 0.833 | 0.885 | 1543.2 | 0.735 | 0.758 | coding |
| qwen2.5-coder:latest | 12.8 | 0.850 | 0.910 | 1228.2 | 0.667 | 0.694 | coding |
| qwen2.5-coder:7b | 12.7 | 0.850 | 0.910 | 1231.9 | 0.666 | 0.693 | coding |
| qwen2.5-coder:14B | 6.6 | 0.850 | 0.931 | 2195.9 | 0.572 | 0.609 | coding |
| codellama:34b | 3.2 | 0.833 | 0.586 | 4244.1 | 0.437 | 0.326 | coding |
| llama3.2:3b | 22.3 | 0.890 | 0.954 | 644.2 | 0.785 | 0.814 | general |
| llama3.1:8b | 11.8 | 0.823 | 0.877 | 2249.3 | 0.596 | 0.621 | general |
| gemma3:12b-it-q4_K_M | 6.4 | 0.873 | 0.966 | 6355.8 | 0.441 | 0.483 | general |

### Current Slot Assignments (model_selection.json)

| Slot | Socket | Role | Model | Composite |
|------|--------|------|-------|-----------|
| 1 | Node 1 (port 11434) | General (locked) | llama3.2:3b | 0.814 |
| 2 | Node 1 (port 11434) | General (locked) | llama3.1:8b | 0.621 |
| 3 | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:16b | 0.738 |
| 4 | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:latest | 0.735 |
| 5 | Node 1 (port 11434) | General (rotate) | gemma3:12b-it-q4_K_M | 0.483 |
| 6 | Node 0 (port 11435) | Coding (rotate) | qwen2.5-coder:latest | 0.667 |

### Tuning Variable Status

| Variable | Value | Status |
|----------|-------|--------|
| `benchmark_num_predict` | 500 | Optimal — rubric ceiling is now the binding constraint |
| `benchmark_large_timeout` | 480s | Adequate — 6–20x margin at current 3–25 tok/sec speeds |
| `benchmark_toks_norm_ceiling` | 40 | Correct — fastest model at 62.5% of ceiling |
| `benchmark_coding_threshold` | 0.10 | Correct — name-pattern fallback handling remaining cases |
| Scoring weights | 0.45/0.30/0.25 | Appropriate for interactive serving platform |

### Findings

**Finding 1 — num_predict=500 confirmed correct.** Every model improved on coding_quality
(+0.023 to +0.050). No timeouts observed. The rubric ceiling is now the binding constraint;
further increases (700+) would yield at most +0.02 additional improvement.

**Finding 2 — Coding quality inversion narrowed (expected, not a bug).** Coding specialists
score lower on coding than general quality because general prompts don't require `assert`,
`test_def`, or `type_hint` (the hardest scoring markers). The gap halved from ~−0.110 to
~−0.052 vs. Run 3, confirming truncation was part of the cause. Name-pattern fallback
continues to correctly classify these models.

**Finding 3 — deepseek-coder-v2:16b and :latest may be the same weights (ACTION REQUIRED).**
Both share identical quality scores (0.833/0.885) and nearly identical throughput (24.5 vs.
25.0 tok/sec). In Ollama, `:latest` typically resolves to the same weights as the default
variant. If confirmed identical, slots 3 and 4 hold duplicate models — zero benefit, wasted
VRAM. See Testing Needed for verification steps.

**Finding 4 — qwen2.5-coder:latest and :7b are near-identical (informational).** Composites
of 0.667 vs. 0.666. Lower impact since only one is active in slot 6 at a time.

**Finding 5 — llama3.2:3b outperforms coding specialists on coding composite (informational).**
coding_composite=0.785 beats all dedicated coding models. Mathematically correct: speed
(22.3 tok/sec) and latency (644ms) dominate. Correctly classified general because
general_composite (0.814) > coding_composite (0.785), delta < 0.10 threshold.

**Finding 6 — codellama:34b correctly excluded.** 3.2 tok/sec, general_quality=0.586 falls
below min_quality_score=0.6. Scoring system worked as designed.

---

## Testing Needed

### Finding 3 — Verify deepseek-coder-v2:16b vs :latest digest

Run on `ai_server`:

```bash
ollama show deepseek-coder-v2:16b --modelfile | grep FROM
ollama show deepseek-coder-v2:latest --modelfile | grep FROM
```

**If digests match (same weights):** update `model_selection.json` slot4_coding manually
(or remove one deepseek variant and re-run `03_benchmark.yml`) to redirect slot 4 to
`qwen2.5-coder:14B` (composite=0.572) or another diverse candidate for model diversity.

**If digests differ (different weights):** no action — the pipeline is working as designed.

### Regression check after any slot4 change

If slot4 is redirected, run:

```bash
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

Confirm both warmup services start cleanly:

```bash
systemctl status ollama-warmup.service ollama-warmup-node0.service
```

---

# Addendum — Run 5 Review (post deepseek:latest removal)

## Run History (all five runs)

| Run | Timestamp | Condition | Models | Result |
|-----|-----------|-----------|--------|--------|
| 1 | 20260309T080551 | Broken NUMA (membind + CPUAffinity) | — | quality=0, tok/sec≈0.0–0.1 |
| 2 | 20260309T174604 | Broken NUMA (same bug) | — | quality=0, tok/sec=0.1 |
| 3 | 20260310T094843 | Post-NUMA-fix, num_predict=300 | 4 | quality=0.78–0.97, tok/sec=6.5–22.8 |
| 4 | 20260310T110632 | num_predict=500, deepseek:latest present | 9 | quality=0.83–0.97, tok/sec=3.2–25.0 |
| 5 | 20260310T122818 | num_predict=500, deepseek:latest removed | 8 | quality=0.83–0.97, tok/sec=3.2–24.5 |

## Run 4 → Run 5 Comparison (all common models)

| Model | R4 tok/sec | R5 tok/sec | R4 coding_comp | R5 coding_comp | Delta |
|-------|-----------|-----------|----------------|----------------|-------|
| deepseek-coder-v2:16b | 24.5 | 24.1 | 0.738 | 0.727 | −0.011 (noise) |
| qwen2.5-coder:latest | 12.8 | 12.4 | 0.667 | 0.671 | +0.004 (noise) |
| qwen2.5-coder:7b | 12.7 | 12.6 | 0.666 | 0.674 | +0.008 (noise) |
| qwen2.5-coder:14B | 6.6 | 6.6 | 0.572 | 0.573 | +0.001 (noise) |
| llama3.2:3b | 22.3 | 24.5 | 0.785 | 0.806 | +0.021 (notable) |
| llama3.1:8b | 11.8 | 11.9 | 0.596 | 0.600 | +0.004 (noise) |
| gemma3:12b-it-q4_K_M | 6.4 | 6.2 | 0.441 | 0.439 | −0.002 (noise) |
| codellama:34b | 3.2 | 3.2 | 0.437 | 0.436 | −0.001 (noise) |

Quality scores (coding_quality, general_quality) are **identical** across both runs —
confirming rubric scores are stable and deterministic at num_predict=500.

## Run 5 Slot Assignments (model_selection.json)

| Slot | Socket | Role | Model | Composite |
|------|--------|------|-------|-----------|
| 1 | Node 1 (port 11434) | General (locked) | llama3.2:3b | 0.835 |
| 2 | Node 1 (port 11434) | General (locked) | llama3.1:8b | 0.624 |
| 5 | Node 1 (port 11434) | General (rotate) | gemma3:12b-it-q4_K_M | 0.481 |
| 3 | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:16b | 0.727 |
| 4 | Node 0 (port 11435) | Coding (locked) | qwen2.5-coder:7b | 0.674 |
| 6 | Node 0 (port 11435) | Coding (rotate) | qwen2.5-coder:latest | 0.671 |

Note: slot4 is `qwen2.5-coder:7b` — the pipeline correctly ranked it #2 coding (0.674),
superseding the manual `qwen2.5-coder:14B` edit made earlier this session.

## Findings

**Finding 1 — System is stable; tuning parameters remain optimal (no action).** All quality
scores are identical between Run 4 and Run 5. Speed and latency deltas are within normal
run-to-run variance (±0.4 tok/sec, ±200ms TTFT). No tuning changes needed.

| Variable | Value | Status |
|----------|-------|--------|
| `benchmark_num_predict` | 500 | Optimal — rubric ceiling is binding constraint |
| `benchmark_large_timeout` | 480s | Adequate — 6–20x margin at 3–25 tok/sec |
| `benchmark_toks_norm_ceiling` | 40 | Correct — fastest model at 61% of ceiling |
| `benchmark_coding_threshold` | 0.10 | Correct — name-pattern fallback working |
| Scoring weights | 0.45/0.30/0.25 | Appropriate for interactive serving |

**Finding 2 — llama3.2:3b improved after deepseek:latest removal (informational).**
tok/sec: 22.3 → 24.5 (+2.2), general_composite: 0.814 → 0.835 (+0.021). Likely cause:
removing one large model reduced memory pressure / NUMA contention during warmup. The 3b
model benefits most as it runs fastest and competes most for memory bandwidth.

**Finding 3 — qwen2.5-coder:7b and :latest confirmed duplicate weights (RESOLVED).**
Run 5 slot4=`:7b` (0.674) and slot6=`:latest` (0.671) showed identical quality scores
(coding=0.850, general=0.910) and nearly identical throughput (~12.4–12.8 tok/sec) across
both runs — same pattern as the deepseek duplicate. Verified on ai_server:

```
qwen2.5-coder:7b    → sha256-60e05f2100071479f596b964f89f510f057ce397ea22f2833a0cfe029bfc2463
qwen2.5-coder:latest → sha256-60e05f2100071479f596b964f89f510f057ce397ea22f2833a0cfe029bfc2463
```

Digests match. `qwen2.5-coder:latest` removed. Next step: re-run `03_benchmark.yml` (Run 6)
to promote `qwen2.5-coder:14B` to slot6_rotate, achieving genuine speed/quality diversity
on Node 0:
- slot3: deepseek-coder-v2:16b — fast+deep (24 tok/sec, 16B)
- slot4: qwen2.5-coder:7b — fast+light (12.6 tok/sec, 7B)
- slot6: qwen2.5-coder:14B — slower+richer quality (6.6 tok/sec, 14B)

**Finding 4 — gemma3:12b latency_score=0 is persistent (informational, no action).**
TTFT consistently 6.1–6.4 seconds, above the 5000ms floor → latency_score=0 every run.
Hardware-limited (large quant loading time on Node 1), not a tuning issue. The model
correctly holds slot5_general_rotate on the strength of general_quality=0.966. The latency
penalty is working as intended.

**Finding 5 — codellama:34b remains correctly excluded (informational, no action).**
composite=0.436, general_quality=0.586 — below both min_composite_score=0.55 and
min_quality_score=0.6 every run. Pipeline working as designed.

## Next Action

Run 6: re-benchmark after `qwen2.5-coder:latest` removal to promote `qwen2.5-coder:14B`
to slot6_rotate and achieve model diversity on Node 0.

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml && \
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

---

# Addendum — Run 6 Review (post qwen2.5-coder:latest removal)

## Run History (all six runs)

| Run | Timestamp | Condition | Models | Result |
|-----|-----------|-----------|--------|--------|
| 1 | 20260309T080551 | Broken NUMA (membind + CPUAffinity) | — | quality=0, tok/sec≈0.0–0.1 |
| 2 | 20260309T174604 | Broken NUMA (same bug) | — | quality=0, tok/sec=0.1 |
| 3 | 20260310T094843 | Post-NUMA-fix, num_predict=300 | 4 | quality=0.78–0.97, tok/sec=6.5–22.8 |
| 4 | 20260310T110632 | num_predict=500, deepseek:latest present | 9 | quality=0.83–0.97, tok/sec=3.2–25.0 |
| 5 | 20260310T122818 | num_predict=500, deepseek:latest removed | 8 | quality=0.83–0.97, tok/sec=3.2–24.5 |
| 6 | 20260310T160815 | num_predict=500, qwen2.5-coder:latest removed | 8 | quality=0.83–0.97, tok/sec=3.2–24.2 |

## Full Run 6 Results

| Model | tok/sec | coding_q | general_q | latency_ms | coding_comp | general_comp | category |
|-------|---------|----------|-----------|------------|-------------|--------------|----------|
| deepseek-coder-v2:16b | 24.2 | 0.833 | 0.885 | 1383.8 | 0.737 | 0.760 | coding |
| deepseek-coder-v2:latest | 24.1 | 0.833 | 0.885 | 1411.4 | 0.735 | 0.759 | coding |
| qwen2.5-coder:7b | 12.6 | 0.850 | 0.910 | 1210.0 | 0.666 | 0.693 | coding |
| qwen2.5-coder:14B | 6.6 | 0.850 | 0.931 | 2181.0 | 0.573 | 0.609 | coding |
| codellama:34b | 3.2 | 0.833 | 0.586 | 4336.2 | 0.432 | 0.321 | coding |
| llama3.2:3b | 24.2 | 0.890 | 0.954 | 581.0 | 0.803 | 0.832 | general |
| llama3.1:8b | 11.8 | 0.823 | 0.877 | 2183.4 | 0.600 | 0.624 | general |
| gemma3:12b-it-q4_K_M | 6.2 | 0.873 | 0.966 | 5540.1 | 0.440 | 0.482 | general |

## Run 5 → Run 6 Comparison (all common models)

| Model | R5 tok/sec | R6 tok/sec | R5 coding_comp | R6 coding_comp | Delta |
|-------|-----------|-----------|----------------|----------------|-------|
| deepseek-coder-v2:16b | 24.1 | 24.2 | 0.727 | 0.737 | +0.010 (noise) |
| qwen2.5-coder:7b | 12.6 | 12.6 | 0.674 | 0.666 | −0.008 (noise) |
| qwen2.5-coder:14B | 6.6 | 6.6 | 0.573 | 0.573 | 0.000 |
| llama3.2:3b | 24.5 | 24.2 | 0.806 | 0.803 | −0.003 (noise) |
| llama3.1:8b | 11.9 | 11.8 | 0.600 | 0.600 | 0.000 |
| gemma3:12b-it-q4_K_M | 6.2 | 6.2 | 0.439 | 0.440 | +0.001 (noise) |
| codellama:34b | 3.2 | 3.2 | 0.436 | 0.432 | −0.004 (noise) |

Quality scores are **identical** across all common models. All composites within run-to-run
noise (≤ ±0.010). Rubric confirmed deterministic across 6 runs.

## Run 6 Slot Assignments (model_selection.json — current state)

| Slot | Socket | Role | Model | Composite |
|------|--------|------|-------|-----------|
| 1 | Node 1 (port 11434) | General (locked) | llama3.2:3b | 0.832 |
| 2 | Node 1 (port 11434) | General (locked) | llama3.1:8b | 0.624 |
| 5 | Node 1 (port 11434) | General (rotate) | gemma3:12b-it-q4_K_M | 0.482 |
| 3 | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:16b | 0.737 |
| 4 | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:latest | 0.735 ← REGRESSION |
| 6 | Node 0 (port 11435) | Coding (rotate) | qwen2.5-coder:7b | 0.666 |

## Findings

**Finding 1 — deepseek-coder-v2:latest re-appeared in slot4 (REGRESSION, now fixed).**
Previously confirmed duplicate of `:16b` and removed after Run 4. Re-appeared in Run 6
because `group_vars/all.yml` contained two pull sources:

1. `baseline_models` (line 121): `"deepseek-coder-v2"` — untagged, Ollama resolves to
   `:latest`, re-pulling the duplicate on every benchmark run.
2. `candidate_models`: explicit `"deepseek-coder-v2:latest"` entry — unconditionally pulls
   `:latest` as a testable model.

**Fix applied to `inventory/group_vars/all.yml`:**
- `baseline_models`: changed `"deepseek-coder-v2"` → `"deepseek-coder-v2:16b"` (explicit tag)
- `candidate_models`: removed the `deepseek-coder-v2:latest` entry entirely

**Also required on ai_server:** `ollama rm deepseek-coder-v2:latest`

**Finding 2 — All scores and tuning variables remain stable (no action).** Every delta vs
Run 5 is within noise (≤ ±0.010 composite, quality scores identical). The rubric is
confirmed deterministic across 6 runs.

| Variable | Value | Status |
|----------|-------|--------|
| `benchmark_num_predict` | 500 | Optimal |
| `benchmark_large_timeout` | 480s | Adequate |
| `benchmark_toks_norm_ceiling` | 40 | Correct |
| `benchmark_coding_threshold` | 0.10 | Correct |

**Finding 3 — qwen2.5-coder:14B not yet in slot6 (consequence of Finding 1).** With
deepseek:latest occupying slot4, the coding rank yields:
  #1 deepseek:16b (0.737) → slot3, #2 deepseek:latest (0.735) → slot4,
  #3 qwen:7b (0.666) → slot6, #4 qwen:14B (0.573) → excluded.
After deepseek:latest is permanently removed, Run 7 expected layout:
  slot3=deepseek:16b, slot4=qwen:7b, slot6=qwen:14B.

**Finding 4 — gemma3:12b TTFT=5540ms (informational, no action).** Persistently above
5000ms floor → latency_score=0 every run. Hardware-limited, not a tuning issue.
Correctly holds slot5_general_rotate on general_quality=0.966.

**Finding 5 — codellama:34b correctly excluded again (informational, no action).**
composite=0.432, general_quality=0.586 — below both thresholds. Pipeline working as designed.

## Next Action

1. Remove duplicate from ai_server: `ollama rm deepseek-coder-v2:latest`
2. Run 7 (clean benchmark):

```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml && \
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```

Expected Run 7: slot4=`qwen2.5-coder:7b`, slot6=`qwen2.5-coder:14B`,
`deepseek-coder-v2:latest` absent from `all_metrics`.

---

# Addendum — Run 7 Review (target Node 0 layout achieved, session closed)

## Run History (all seven runs)

| Run | Timestamp | Condition | Models | Result |
|-----|-----------|-----------|--------|--------|
| 1 | 20260309T080551 | Broken NUMA (membind + CPUAffinity) | — | quality=0, tok/sec≈0.0–0.1 |
| 2 | 20260309T174604 | Broken NUMA (same bug) | — | quality=0, tok/sec=0.1 |
| 3 | 20260310T094843 | Post-NUMA-fix, num_predict=300 | 4 | quality=0.78–0.97, tok/sec=6.5–22.8 |
| 4 | 20260310T110632 | num_predict=500, deepseek:latest present | 9 | quality=0.83–0.97, tok/sec=3.2–25.0 |
| 5 | 20260310T122818 | num_predict=500, deepseek:latest removed | 8 | quality=0.83–0.97, tok/sec=3.2–24.5 |
| 6 | 20260310T160815 | num_predict=500, qwen2.5-coder:latest removed | 8 | quality=0.83–0.97, tok/sec=3.2–24.2 |
| 7 | 20260310T170013 | group_vars fix applied, deepseek:latest absent | 7 | quality=0.83–0.97, tok/sec=3.2–23.5 |

## Full Run 7 Results

| Model | tok/sec | coding_q | general_q | latency_ms | coding_comp | general_comp | category |
|-------|---------|----------|-----------|------------|-------------|--------------|----------|
| deepseek-coder-v2:16b | 23.5 | 0.833 | 0.885 | 1568.5 | 0.723 | 0.746 | coding |
| qwen2.5-coder:7b | 12.5 | 0.850 | 0.910 | 1431.0 | 0.655 | 0.682 | coding |
| qwen2.5-coder:14B | 6.6 | 0.850 | 0.931 | 2229.7 | 0.570 | 0.607 | coding |
| codellama:34b | 3.2 | 0.833 | 0.586 | 4235.4 | 0.437 | 0.326 | coding |
| llama3.2:3b | 23.0 | 0.890 | 0.954 | 754.8 | 0.786 | 0.814 | general |
| llama3.1:8b | 11.8 | 0.823 | 0.877 | 2202.0 | 0.599 | 0.623 | general |
| gemma3:12b-it-q4_K_M | 6.1 | 0.873 | 0.966 | 5941.9 | 0.439 | 0.481 | general |

`deepseek-coder-v2:latest` **absent** from `all_metrics` — group_vars fix verified working.

## Run 6 → Run 7 Comparison (all common models)

| Model | R6 tok/sec | R7 tok/sec | R6 coding_comp | R7 coding_comp | Delta |
|-------|-----------|-----------|----------------|----------------|-------|
| deepseek-coder-v2:16b | 24.2 | 23.5 | 0.737 | 0.723 | −0.014 (noise) |
| qwen2.5-coder:7b | 12.6 | 12.5 | 0.666 | 0.655 | −0.011 (noise) |
| qwen2.5-coder:14B | 6.6 | 6.6 | 0.573 | 0.570 | −0.003 (noise) |
| llama3.2:3b | 24.2 | 23.0 | 0.803 | 0.786 | −0.017 (noise) |
| llama3.1:8b | 11.8 | 11.8 | 0.600 | 0.599 | −0.001 (noise) |
| gemma3:12b-it-q4_K_M | 6.2 | 6.1 | 0.440 | 0.439 | −0.001 (noise) |
| codellama:34b | 3.2 | 3.2 | 0.432 | 0.437 | +0.005 (noise) |

Quality scores are **identical** across all common models. All composites within run-to-run
noise (≤ ±0.017). Rubric confirmed deterministic across 7 runs.

## Run 7 Slot Assignments (final, confirmed clean)

| Slot | Socket | Role | Model | Composite |
|------|--------|------|-------|-----------|
| 1 | Node 1 (port 11434) | General (locked) | llama3.2:3b | 0.814 |
| 2 | Node 1 (port 11434) | General (locked) | llama3.1:8b | 0.623 |
| 5 | Node 1 (port 11434) | General (rotate) | gemma3:12b-it-q4_K_M | 0.481 |
| 3 | Node 0 (port 11435) | Coding (locked) | deepseek-coder-v2:16b | 0.723 |
| 4 | Node 0 (port 11435) | Coding (locked) | qwen2.5-coder:7b | 0.655 ✅ |
| 6 | Node 0 (port 11435) | Coding (rotate) | qwen2.5-coder:14B | 0.570 ✅ |

## Findings

**Finding 1 — Target Node 0 diversity layout achieved (RESOLVED).** Run 7 confirms the
intended three-tier Node 0 layout:
- slot3: deepseek-coder-v2:16b — deep specialist (23.5 tok/sec, 16B params)
- slot4: qwen2.5-coder:7b — fast+light (12.5 tok/sec, 7B params)
- slot6: qwen2.5-coder:14B — slower+richer (6.6 tok/sec, 14B params)

All three are genuinely distinct models with different speed/quality tradeoffs.

**Finding 2 — group_vars fix verified working (RESOLVED).** `deepseek-coder-v2:latest` is
absent from `all_metrics`. Explicit `:16b` tag in `baseline_models` prevents Ollama from
resolving to `:latest` on subsequent runs. The fix is durable — re-running `03_benchmark.yml`
will not re-introduce the duplicate.

**Finding 3 — All scores and tuning variables stable (no action).** Every delta vs Run 6 is
within noise (≤ ±0.017 composite, quality scores identical). The pipeline is confirmed
deterministic and stable.

| Variable | Value | Status |
|----------|-------|--------|
| `benchmark_num_predict` | 500 | Optimal |
| `benchmark_large_timeout` | 480s | Adequate |
| `benchmark_toks_norm_ceiling` | 40 | Correct |
| `benchmark_coding_threshold` | 0.10 | Correct |

**Finding 4 — Benchmark pipeline declared stable. Session closed.** Seven runs over two
days confirmed: NUMA fix correct, scoring rubric deterministic, duplicate-model detection
pattern documented, group_vars idempotent. No further benchmark runs or tuning changes are
needed unless new models are added to `candidate_models`.
