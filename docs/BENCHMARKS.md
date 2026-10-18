# Benchmarks and evidence

These measurements answer two different questions: whether adding an iPad helps a memory-constrained Mac, and whether retained LlamaPad changes improve the distributed engine. They are separate experiments and must not be combined into a cumulative speedup.

## Hardware, model and measurement scope

- Apple M1 Pro Mac, 16 GiB RAM, and Apple M1 iPad, 16 GiB RAM, on stock operating systems. The Mac is **M1 Pro**, not the base M1. No equivalent performance claim is made for other chips.
- TCP RPC through an `iproxy` USB tunnel. A negotiated 10 Gb/s USB connection is not a measured 40 Gb/s Thunderbolt IP link.
- llama.cpp upstream revision `b76b13379d3b7d67ab0bc424516bb6fd2522bd8e`, with the LlamaPad integration and experiment settings described below. This is not an unrestricted comparison with every stock llama.cpp configuration.
- LFM2.5-24B-A2B Q4_K_M is the same 14,526,258,464-byte GGUF throughout the LFM comparisons. SHA-256: `d3334405b96228eb9908cdebb5c6194908f2da64282bda852afc3a3910c64e7d`. No requantization or weight changes were made.
- Short-context, single-sequence requests, context capacity 2,048, batch 256, microbatch 64, F16 KV and Flash Attention. Greedy sampling, no prompt-prefix reuse and zero thinking budget. A separate warmup is excluded. Weight/expert caches can warm normally.
- Generation throughput is `sum(emitted tokens) * 1000 / sum(native generation milliseconds)`. It excludes startup, warmup, prompt processing and explicit cooling waits; it is not total request throughput or first-token latency. This emitted-token convention includes the first token, which is produced during prompt processing; the JSON also reports rates with one token per request removed.
- Many replies hit their requested output cap. These are bounded performance and output-identity checks, not complete-answer quality tests, long-context qualification or statistical confidence intervals.

Measurements were recorded on 15-17 October 2026. Background desktop activity and system memory pressure were present. System-wide paging counters cannot be attributed exclusively to inference. Profiling runs are excluded from the throughput tables.

## Adding the iPad: LFM2.5-24B-A2B Q4_K_M

Three explanation/code/planning prompts, two rounds per mode, one excluded warmup and a 128-token output cap. Each mode emitted 742 measured tokens in six replies. All six paired returned texts, finish reasons and token counts match in the published evidence export.

| Configuration | Pooled generation tokens/s | Individual native request-rate range | Prompt tokens/s |
| --- | ---: | ---: | ---: |
| Mac alone: CPU MoE with 8 GiB upstream GPU expert cache, six CPU threads | 4.47 | 3.83-5.77 | 5.04 |
| Mac + iPad: 70/30 split, iPad first, two coordinator CPU threads | **29.59** | 28.69-29.84 | 106.63 |
| Mac + iPad: 80/20 alternative | 30.26 | 29.48-30.59 | 111.10 |

The selected 70/30 placement gives **6.62x** the tested cached Mac-only generation throughput. It keeps transformer blocks and expert weights on the two GPUs, with the output projection on Mac. It avoids the expensive memory behavior observed in the Mac-only fallback. This is a practical capacity/placement benefit under the measured desktop conditions, not a pure GPU-kernel comparison or proof that the Mac-only settings are globally optimal.

The Mac's reported recommended Metal working set was about 11.84 GiB, below the 13.53 GiB model file before runtime state and other applications. The Mac-only chat interval recorded 83.33 GiB of system-wide page-ins; the 70/30 interval recorded 0.18 GiB. Those counters support a memory bottleneck but include other processes and differently sized time intervals. They do not isolate SSD reads caused by this process.

The 80/20 alternative was only 2.25% faster than 70/30 and left 1,384 MiB less reported Metal working-set headroom. Its interval recorded 0.236 GiB of system swap-outs, versus zero for 70/30. The original selection therefore kept 70/30. A later 55/45 placement saves a further 2.0446 GiB of Mac model buffers versus 70/30; one six-request confirmation measured 29.72 tokens/s with matching outputs. That placement confirmation was not an interleaved speed comparison, and allocation saved is not physically free RAM.

## Larger-model capacity: Qwen3.6-27B

| Model | Mac alone | Mac + iPad ordinary decoding | Mac + iPad MTP4 |
| --- | ---: | ---: | ---: |
| Qwen3.6-27B, native-MTP-preserved Q4_K_M, 16.03 GiB GGUF | Guarded during startup; no measured rate | 3.56 tokens/s | **8.15 tokens/s** |

The exact model filename and size are in the JSON. The series uses four explanation/code/planning/editing requests per launch, repeated over two launches per successful method, a 96-token cap, six coordinator CPU threads and an excluded 32-token warmup. All eight paired results match, including returned reasoning text, finish reason and token count.

The bounded Qwen Mac-only attempt uses 28 GPU layers, an explicit GPU output projection and CPU-mapped remaining weights, with repacking disabled. It is stopped on sustained warning-level memory pressure after 14.68 seconds, before API readiness. It is **not** assigned a zero-token rate, and no Mac-to-RPC ratio is calculated. This does not prove that every alternative Mac-only configuration is impossible.

Qwen RPC uses 40/60 Mac/iPad placement with the output projection on Mac. The nominal-start RPC/MTP/MTP/RPC comparison waits for nominal iPad thermal-category samples over at least 60 idle seconds before each warmup. Ordinary RPC reaches serious thermal pressure by the end of both runs; MTP endpoints remain nominal. The observed MTP gain is **129.0%**, including thermal behavior differences. It is not an isolated kernel gain or a guarantee of indefinitely sustained speed. MTP uses the auxiliary head already present in this GGUF; this is upstream speculative decoding configured by LlamaPad, not a new MTP algorithm or a separate drafter model.

These later capacity trials cap Mac Metal model buffers at 7,737.72 MiB. Runtime buffers, mapped host allocations and other apps are additional. The memory guard and this cap are experimental measurement policies, not a guarantee of 2 GiB free RAM or a default launcher guard.

## Memory for larger quants and KV state

The comparison is scoped to memory-constrained workloads. A smaller model that already fits on one device does not establish the value of added capacity and is outside these tables.

The measured 55/45 LFM placement moves about 2.04 GiB of model allocation off Mac relative to the earlier 70/30 placement. Reducing Mac weight residency can leave budget for a higher-precision model, more KV/recurrent state, or other runtime allocations. This is distributed placement, not a single pooled 32 GiB allocation; both devices still need their own runtime headroom.

All published timings use a 2,048-token context capacity. No matched higher-quant comparison, maximum-context measurement or larger-KV throughput result is claimed. Those require separate runs with the same model family and explicit quantization, context, memory and output checks. The existing evidence establishes a distributed memory/capacity benefit for the tested large models, rather than a measured long-context or quantization gain.

## Retained engine changes

### Router/convolution fusion and submission settings

An unprofiled control/candidate/candidate/control sequence used fresh launches, the 70/30 split and no speculation. Each launch answered the same three prompts twice after warmup, with temperature zero, seed 42 and a 128-token cap. Each group emitted 1,484 tokens across twelve replies.

| Group | Generation tokens/s | Prompt tokens/s | Paired returned outputs |
| --- | ---: | ---: | --- |
| Integration control, experimental settings off | 29.11 | 106.43 | Reference |
| Router + gated-convolution fusion, three total command buffers on each GPU | **30.11** | 105.18 | **12/12 identical** |

The combined generation gain is **3.46%**. This compares opt-in fusions and submission settings within the LlamaPad-integrated engine; it does not isolate each flag, each GPU's contribution or stock llama.cpp as a whole. Prompt processing did not improve. Available iPad snapshots report nominal thermals, but system paging activity was present. Small samples and ABBA ordering do not establish a statistical confidence interval.

Both Mac and iPad enable:

```text
LLAMAPAD_METAL_SIGMOID_ROUTER=1
LLAMAPAD_METAL_GATED_CONV=1
LLAMAPAD_METAL_COMMAND_BUFFERS=2
```

The last value means **two extra buffers, three total**. Defaults are unchanged. Upstream Metal, Accelerate and Flash Attention remain the foundation. No driver replacement or operating-system modification is involved.

### Canonical replay and longer n-gram proposals

The later 55/45 comparison keeps weights, routing/convolution settings and three command buffers per GPU fixed. It compares the qualified eight-token n-gram preset with 26-token proposals and canonical nine-token target verification. Lookup length is 16, minimum proposal length four and the Q4_K/Q6_K few-row threshold is 17 on both GPUs. The new replay handling is in the **Mac coordinator**; no iPad shader or driver change is part of this experiment.

The contiguous control/candidate/candidate/control sequence has twelve distinct prompts per launch: five fresh-chat and seven editing cases. Each group emits 4,114 tokens in 24 replies. The first control is the immediately preceding final control from the rejected 64-token experiment, reused once; it is not an additional independent run. Prompt/history lookup tables start fresh per launch, and warmups do not seed answers.

| Workload | Eight-token control | Canonical 26-token candidate | Generation change | Request wall-time change |
| --- | ---: | ---: | ---: | ---: |
| Fresh chat, 10 replies/group | 30.25 | 29.79 | **-1.53%** | +1.47% |
| Editing, 14 replies/group | 38.49 | **41.57** | **+7.98%** | -6.17% |
| Full suite, 24 replies/group | 35.89 | **37.61** | **+4.79%** | -3.90% |

All 24 paired returned outputs, finish reasons and token counts match, as do warmups. Two additional previously untested TOML/SQL editing cases match but are excluded from throughput. These bounded greedy checks do not prove numerical equivalence for every prompt, grammar, sampler, context length or Apple chip. N-gram lookup itself is upstream functionality; the retained code change aligns verification/replay arithmetic and the selected proposal limit. No extra draft model is loaded.

Mac model buffers remain 7,737.70 MiB, iPad model buffers 6,107.76 MiB and iPad backend allocation about 6.00 GiB. The maximum extra measured Mac peak process footprint is 8.5 MiB versus control. That process-footprint metric excludes reclaimable mapped model pages and is not total model RAM. The earlier 2.0446 GiB model-allocation reduction remains intact.

The candidate enables coordinator `LLAMAPAD_METAL_STABLE_REPLAY=1` and `--ngram-draft 26 --ngram-match 16 --ngram-min 4`; control uses eight drafts and stable replay off. This is an editing/reuse improvement. Fresh chat proposed no drafts and did not get faster. Separate experiments' gains must not be added or multiplied.

## Scope of the improvement claims

There is no matched before/after standalone iPad-only or Mac-only benchmark establishing an engine-code speedup for each device separately. The retained fusion result is a distributed result with changes enabled on both GPUs; the replay result is a coordinator improvement. The demonstrated 1.2B iPad-only chat rate is a different model and is not used to claim a 24B speedup. Ordinary 24B chat has not reached 60 tokens/s.

## Reproduction and public evidence

[benchmark-results.json](benchmark-results.json) contains allowlisted model identifiers, settings, per-request token counts/timings, output identity hashes and aggregates exported from the completed local runs. Rates and ratios can be recomputed from those samples. Returned-text identity hashes cover content plus reasoning; finish reasons and token counts are recorded separately. Hash equality is evidence of agreement in these samples, not an independent verification of the timing measurements or model quality.

No raw prompts/responses, test suites, model weights, paths to personal files, account/device identifiers, network addresses, signing data or raw device logs are published. Original records stay private. The public summaries document the recorded comparison; they are not a fully public replay corpus or an independent third-party replication.

To compare the original LFM capacity modes with your own matching request set, first stop other coordinators/clients, use the same model, and run **one mode at a time**. Start Mac-only with:

```sh
python3 Scripts/run-rpc.py /path/to/LFM2.5-24B-A2B-Q4_K_M.gguf \
  --local-only --gpu-layers 999 --cpu-moe --moe-cache-mib 8192 --threads 6 \
  --context 2048 --batch 256 --micro-batch 64 --no-repack --reasoning-budget 0
```

After stopping it, start RPC with LlamaPad foreground on the connected iPad:

```sh
python3 Scripts/run-rpc.py /path/to/LFM2.5-24B-A2B-Q4_K_M.gguf \
  --device DEVICE_UDID --ipad-first --split 70,30 --threads 2 \
  --node-memory 10240 --context 2048 --batch 256 --micro-batch 64 \
  --no-repack --reasoning-budget 0
```

Use temperature zero, seed 42, `cache_prompt: false`, identical prompts and output caps, and separate excluded warmups. Keep ordinary decoding for that comparison. For the later engine comparisons, also match the flags and the 70/30 or 55/45 placement described in their sections. Export server-native prompt/generation timings separately from request wall time. Check complete returned outputs, memory pressure, actual buffer placement and thermal endpoints before accepting a result. Stop a configuration that exceeds your chosen memory policy; do not turn an interrupted startup into a throughput claim.
