# Bonsai 2 27B on Apple Silicon: a 27B in 7 GB at 34 tok/s

Measured recipe for PrismML's **Bonsai 2 27B** — a ternary (1.72 bits/weight) quant
of Qwen3.8-27B — on a Mac Studio M4 Max and a base Mac mini M4, using the prism
llama.cpp fork the model requires. Same harness and prompts as our
[Qwen3.8-27B oMLX+MTP recipe](https://github.com/Weschera/Qwen3.8-27B-oMLX-MTP-Mac),
so the numbers are directly comparable to the full-size model on the same machine.

Published the day the model dropped (2026-09-17). Every number is from a real
run; raw JSON and full benchmark reports are in this repo.

## Results

Single stream, temperature 0, thinking off, 320 generated tokens, ~2.1–2.4K-token
prompts, 3 reps each (`bench-chat.py`, mean; min–max in `results/*.json`).

| Machine | Band | File | Prose tok/s | Code tok/s | Prefill tok/s |
|---|---|---|---:|---:|---:|
| Mac Studio M4 Max, 128 GB | **PQ2_0** (recommended) | 7.2 GB | **34.5** | **34.3** | 242 |
| Mac Studio M4 Max, 128 GB | PTQ1_0 | 5.9 GB | 31.2 | 31.1 | 205 |
| Mac mini M4 (10-core GPU), 24 GB | PQ2_0 | 7.2 GB | 11.0* | — | 33* |

\* Mini row is from the qualification prompt (server `timings`, 145 tokens), not the
3-rep ladder — the ladder is queued behind its Spark Bench run and will replace this.

For scale, on the **same Studio** our full-precision Qwen3.8-27B recipe
(oMLX + ANE prefill + native MTP k=3) does 53.3 prose / 72.1 code. Bonsai 2 is
**~0.65× the speed at 0.42× the size** (7.2 GB vs 17 GB), and the flat
prose = code number is the tell: there is no speculative decoding on this stack, so
it is purely bandwidth-bound.

### Quality: Spark Bench v6.8.3, Mac Studio

Same frozen contract as every model on [wesche.com/dgx](https://wesche.com/dgx):
76 scenarios × 2 repeats, thinking OFF, temperature 0.3, uncapped output, 120 s
socket-inactivity timeout, harness commit `700df0a`.

- **TrueScore 82.4 / 100 — grade B.** Capability 81.3, Operational 83.6.
- Pass@1 90.8 %, Pass@K 82.9 %, median turn 6.1 s.
- Strong: structured output 100, robustness 100, composition 100, code 87, instruction 85.
- Weak: **long-context retrieval 25** (fails the 32-field extraction), visual 70, agentic 73.

Full report: [`results/spark-bench-studio/`](results/spark-bench-studio/). Comparable
same-contract scores on our leaderboard: Qwen3.8-27B 4-bit MTP on this Studio ≈ 89.8
(older v6.8.0 run, quarantined for a flat-planning flag, so treat as indicative), GLM-5.3
Flash EXL3 TP2 on 2 DGX Sparks 89.6, Qwen3.8 Flash-Next NVFP4 on 1 Spark 91.9. Bonsai 2
lands ~7–10 points under the full-precision 27B class, in a file a quarter the size.

Mac mini Spark Bench is running now; its report lands in `results/spark-bench-mini/`.

## Recipe

Tested pins: Bonsai-demo `c398c6e` (2026-09-17), prism llama.cpp release
`prism-b10683-d8f26ee` (build 10683), macOS 26.5.2 (Studio) / 26.4.1 (mini).

```bash
# 1. clone the demo — it downloads the prism llama.cpp binaries AND the model
git clone https://github.com/PrismML-Eng/Bonsai-demo.git ~/projects/bonsai-demo
cd ~/projects/bonsai-demo
BONSAI_FAMILY=bonsai2 BONSAI_MODEL=27B BONSAI_SKIP_MLX=1 \
BONSAI_OPENWEBUI=0 BONSAI_CODE_INTERPRETER=0 ./setup.sh
#   -> bin/mac/llama-server (prism fork) + models/bonsai2-gguf/27B/*PQ2_0.gguf + mmproj

# 2. serve on an OpenAI-compatible port (this repo's wrapper; 131072 ctx on 128 GB)
bash serve.sh                       # PORT=8091 by default
BONSAI_CTX=65536 bash serve.sh      # 24 GB Mac mini

# 3. check
curl http://127.0.0.1:8091/v1/models
```

What the demo script actually launches (verbatim from `scripts/start_llama_server.sh`,
saved in `evidence/`): `-ngl 999 -fa on -c $CTX --temp 0.7 --top-p 0.95 --top-k 20
--min-p 0 --jinja --mmproj <mmproj-Q8_0> --image-max-tokens 1024 --webui-config-file …`.
`--jinja` gives native OpenAI `tool_calls`; the mmproj gives image input.

Thinking defaults **on** and is verbose (8.9K reasoning characters on a 120-word prose
prompt, 3,088 tokens, same 34 tok/s). For chat, cap or disable per request:

```json
{"chat_template_kwargs": {"enable_thinking": false}}
```

or serve with `bash serve.sh --reasoning-budget 2048`.

## Reproduce the numbers

```bash
python3 -m venv .venv && .venv/bin/pip install transformers
BENCH_URL=http://127.0.0.1:8091/v1 BENCH_MODEL=Ternary-Bonsai-2-27B \
.venv/bin/python bench-chat.py --tag mine \
  --model-path <any Qwen3.8-27B tokenizer dir> --out results/mine.json --warmup
```

`bench-chat.py` is byte-for-byte the harness from the oMLX recipe plus one line: an
explicit `chat_template_kwargs.enable_thinking` flag (`BENCH_THINKING=off` default),
because Bonsai 2 thinks by default and the ladder is measured thinking off.

Spark Bench: [Weschera/spark-bench](https://github.com/Weschera/spark-bench) at
`700df0a`, `eval --thinking off --repeats 2 --temperature 0.3 --uncapped --tier all
--timeout 120 --parallelism 1`.

## Gotchas

- **Stock llama.cpp does not run this model.** PQ2_0/PTQ1_0 are rejected as unknown
  types (safe); the dev-repo `Q2_0` band loads on mainline and emits gibberish. Use the
  demo's binaries. If you see garbage, check which `llama-server` you launched first.
- **No MTP / drafter yet.** The model has no MTP heads in the pack, and PrismML has not
  published a Bonsai 2 DSpark drafter (the previous-gen one is target-specific and won't
  load). Their notes say DSpark is a net slowdown on Metal for chat anyway; the win is on
  CUDA. So 34 tok/s is the Mac number for now.
- **PTQ1_0 is ~10 % slower than PQ2_0** on Metal (31 vs 34.5 decode, 205 vs 242 prefill).
  The 1.3 GB saving only matters if you're memory-constrained; on any Mac ≥ 16 GB take
  PQ2_0.
- **Mac mini bind.** The start script binds `127.0.0.1`; `BONSAI_HOST=0.0.0.0` widens
  it but macOS's firewall still blocked LAN clients on ours. We benchmarked through an
  SSH tunnel (`ssh -L 8092:127.0.0.1:8091 mini`), which is also the safe way.
- **Prefill is the tax.** Ternary unpacking makes prompt processing slower than a
  4-bit affine quant of the same model (242 vs 274 tok/s on the Studio, 33 on the mini).
  Long-prompt workloads feel it more than chat.
- Low Power Mode throttles Metal hard; check System Settings → Battery if numbers are
  far off.

## Files

- `serve.sh` — wrapper that launches the demo's tested server flags on a fixed port.
- `bench-chat.py` — the throughput harness (thinking flag added).
- `results/studio-m4max-pq2_0.{json,log}`, `results/studio-m4max-ptq1_0.{json,log}` — raw ladder.
- `results/spark-bench-studio/` — Spark Bench v6.8.3 report (md + html) and per-trial CSV.
- `results/spark-bench-mini/` — same for the Mac mini (pending).
- `evidence/start_llama_server.sh.upstream` — the demo's launcher as tested.

## Credits

- [PrismML](https://huggingface.co/prism-ml) — Bonsai 2 weights, the Hadamard-rotated
  ternary format, and the llama.cpp fork/kernels that run it.
- Qwen team — the Qwen3.8-27B base.
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — the engine prism forked.

Hardware: Mac Studio M4 Max 40-core GPU 128 GB; Mac mini M4 10-core GPU 24 GB.
