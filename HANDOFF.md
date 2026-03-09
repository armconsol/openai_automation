# Session Handoff — 2026-03-09

## Branch
`feature/three-pass-benchmark`

## What Was Just Done

Fixed two bugs that caused near-zero tok/sec and latency=9999 in the concurrent benchmark.

### Bug 1 — Queue contamination (tok/sec ≈ 0.04–0.08)
**Root cause:** Benchmark was firing all 21 requests (3 models × 7 prompts) at once via
async uri. With `OLLAMA_NUM_PARALLEL=2`, only 2 slots run at a time; the other 19 queue.
`eval_duration` includes queue-wait time → tok/sec measured as ~0.18 instead of ~22.

**Fix:** `playbooks/_bench_tier_batch.yml` — replaced the 7 async fire+collect tasks
with 5 synchronous `uri` tasks (no `async`/`poll`). Node1 runs all its prompts first,
then node0. One request at a time = idle slot = clean eval_duration.

Key structural changes:
- No more `_bench_node1_jobs` / `_bench_node0_jobs` intermediate registers
- No more `async_status` collect tasks
- Accumulate tasks now use `item.item` (top-level in sync uri) instead of
  `item._async_job.item` (the old async indirection)
- `timeout` reverted from `benchmark_large_timeout × 15` to plain `benchmark_large_timeout`

### Bug 2 — latency_ms = 9999 (latency_ns = 0)
**Root cause:** Load phase warm-up "Hi" populates KV cache. Benchmark "Hi" hits cache →
`prompt_eval_duration ≈ 0` and `eval_duration ≈ 0` → sum = 0 → latency_ms = 9999.

**Fix:** `playbooks/03_benchmark.yml` line 268 — changed latency measurement from
`eval_duration + prompt_eval_duration` to `resp.total_duration | default(0) | int`.
`total_duration` is true wall-clock end-to-end; never zero for a completed request.

## State of the Branch
Both fixes are committed as `d9a991f`. Nothing is pending.

## Expected Results After Fix
- `avg_tok_per_sec` ≈ 5–25 (was 0.04–0.08)
- `latency_ms` ≈ 300–6000 ms (was 9999)
- Composite scores ≈ 0.50–0.85 (was ≈ 0.45 flat)

## Next Steps
1. Run benchmark to verify the fix:
```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml \
  -e "benchmark_models=llama3.2:3b,qwen2.5-coder:7b,mistral:latest,mistral-nemo:latest"
```
2. If scores look correct, update warm-up slots:
```bash
ansible-playbook playbooks/03_benchmark.yml -K -e @local.yml && \
ansible-playbook playbooks/04_models.yml -K -e @local.yml
```
3. Merge `feature/three-pass-benchmark` into `master` when satisfied.
