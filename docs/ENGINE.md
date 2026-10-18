# Engine changes and tuning

## Pinned source

The engine is based on llama.cpp revision `b76b13379d3b7d67ab0bc424516bb6fd2522bd8e`, recorded in `upstream.lock`. The source under `vendor/llama.cpp` already includes the retained LlamaPad changes. Do not apply the patch a second time.

`patches/0001-llamapad-engine.patch` captures the application/runtime changes against the pinned upstream revision, excluding tests. `patches/0002-source-archive-build.patch` records archive adjustments: removing UI test configuration, preserving engine identity without Git metadata and keeping the upstream build script visible to a new repository. Both can be applied in order to an upstream checkout for source comparison. No previously rejected expert-reuse prototype is included.

## Retained integration

- Controlled RPC start/stop lifecycle, interruptible accept/disconnect handling and budget-aware backend allocation.
- Worker memory, traffic, graph and CPU/GPU-command timing counters used by the app.
- Optional K-quant few-row matrix dispatch thresholds and tuning hooks.
- Optional LFM2MoE sigmoid-router and gated-convolution fusions.
- Optional command-buffer scheduling controls.
- Optional canonical nine-token LFM2MoE speculative verification and replay handling in the Mac coordinator.

Upstream Metal, Accelerate, Flash Attention, memory mapping and capability-dependent kernel dispatch remain the foundation. Newer GPU features are selected through upstream capability and availability checks. A common CPU instruction baseline does not guarantee equivalent speed or numerical behavior on every M-series chip.

## Start conservatively

Use ordinary decoding and default kernel dispatch first. Choose a model and split that leave room for the operating system, KV cache, recurrent state and scratch allocations. Keep the final output projection with the coordinator when suitable for the workload. Models that already fit locally can be faster without RPC.

Compare identical prompts, sampling settings, context and output limits. Record first-token latency separately from generation rate, warm up separately, disable prefix reuse for independent requests and repeat both configurations. Track memory pressure and thermals throughout. Do not infer a kernel speedup from a change in draft acceptance or cooling state.

No private benchmark data or machine-specific performance claims are distributed in this package. The source does not promise a particular token rate.

## Experimental launcher options

| Option | Purpose and limit |
| --- | --- |
| `--mtp-draft 1..8` | Native MTP; requires compatible heads in the target model |
| `--draft-model`, `--draft-tokens`, `--draft-device` | DFlash with a compatible separate draft model; adds memory and verification costs |
| `--ngram-draft`, `--ngram-match`, `--ngram-min` | Prompt/history lookup speculation, useful when output repeats existing text |
| `--mac-k-mma-min-rows`, `--ipad-k-mma-min-rows` | Independent Q4_K/Q6_K few-row MMA thresholds; zero keeps stock selection |
| `--mac-metal-env`, `--ipad-metal-env` | Explicit per-device `LLAMAPAD_METAL_*` or `GGML_METAL_*` environment entries |
| `--no-repack` | Avoid CPU weight repacking allocations |
| `--gpu-layers`, `--override-tensor`, `--cpu-moe`, `--moe-cache-mib` | Capacity/placement controls; CPU and GPU still share each device's physical memory |

LlamaPad hooks include `LLAMAPAD_METAL_COMMAND_BUFFERS` (0-2 extra buffers), `LLAMAPAD_METAL_SIGMOID_ROUTER`, `LLAMAPAD_METAL_GATED_CONV` and coordinator-only `LLAMAPAD_METAL_STABLE_REPLAY`. Ordinary defaults leave experimental features off. Use only hooks understood by the worker's matching source version.

Canonical replay is limited to all-output, single-sequence, causal LFM2MoE generation; the server replay guard is for greedy n-gram speculation. It preserves the prompt microbatch while using nine-token verification units. It is not a general guarantee of batch-independent arithmetic or identical replies for every model, sampler, grammar or device. Larger draft limits can add rejected work and reduce speed. Verify complete outputs against an ordinary/control configuration before relying on a new preset.

The presence of a DSpark or DFlash file does not establish target compatibility. An auxiliary head trained for a different target size cannot be attached generically to another model.

## Upstream changes

Treat revision upgrades as an integration change: update the source, port the lifecycle/telemetry hooks, rebuild both app and coordinator, and re-check model compatibility and RPC behavior. A matching upstream hash alone is insufficient if the LlamaPad patches differ. Keep third-party notices and update the source manifests and patch files with the release.
