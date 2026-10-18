# Using LlamaPad

## Service workspaces

Inference Server and RPC Node have independent settings and connection pages. Only one service can run at a time. Selecting another workspace does not itself stop an active service. Keep the app in the foreground; backgrounding requests shutdown and iPadOS may suspend or terminate the process.

## Inference server

1. Import a complete `.gguf` file through Models, or use Finder file sharing and reopen the app.
2. Select the model, choose Balanced settings and a modest context, and start the server.
3. Open Chat for the integrated llama.cpp interface, or Connect for API addresses and tunnel commands.

Import makes a private copy, so reserve sufficient storage. Split GGUF sets and separate multimodal projector imports are not implemented. Supported architectures, quantizations and chat templates depend on the pinned engine; the filename extension alone does not establish compatibility.

The embedded UI provides conversations, branching, system prompts, sampling controls, reasoning display, Markdown/code and conversation import/export. Attachments, tools and external integrations depend on model support and their configuration. The native API key is supplied only to the exact local server origin.

The HTTP API includes `/health`, `/v1/models`, `/v1/chat/completions`, `/v1/completions`, `/completion`, `/metrics`, `/slots`, `/tokenize`, `/detokenize` and `/apply-template`. `/health` is public. Use the alias and key shown in the app. USB defaults to loopback; Local network listens on all interfaces and requires a key. HTTP traffic is not encrypted.

## RPC node

RPC runs GPU layers assigned by the Mac coordinator. The model can remain on the Mac; the coordinator uploads required tensors, and the worker can cache weights in the app's private cache. Use a matching engine revision and patch set on both devices.

The node exposes one backend for one coordinator. Use layer splitting; tensor-parallel peer collectives are unsupported. Increase the iPad layer share when Mac capacity is the limit, then measure the resulting speed and thermal behavior. The devices do not form a pool of uniform-speed memory.

The automatic USB launcher starts the worker, creates `iproxy`, checks a fresh runtime snapshot and engine revision, and starts a loopback HTTP coordinator. It terminates an existing LlamaPad process to launch the worker; stop active inference and save any UI work first. Its default RPC port is 50052. Use `--device DEVICE_UDID`, or install first to create your own ignored local signing record.

```sh
python3 Scripts/run-rpc.py /path/to/model.gguf \
  --device DEVICE_UDID --ipad-first --split 40,60 \
  --context 2048 --batch 256 --micro-batch 64 --node-memory 8192
```

`--split` always means Mac,iPad. `--ipad-first` places the initial layers on iPad and final layers/output on Mac. `--local-only` runs ordinary Mac decoding without the worker or tunnel. Run `python3 Scripts/run-rpc.py --help` for all launcher options. Run logs and command records are created under the ignored `build/` directory and can contain your model paths and device details.

For manual setup, use the matching `llama-server` binary, start RPC Node in the app and forward port 50052 with `iproxy`. Stop the tunnel when finished. USB TCP forwarding does not itself establish a Thunderbolt Bridge or RDMA link; negotiated connector speed is not measured inference throughput.

## Metrics

| Display | Meaning |
| --- | --- |
| RPC memory | Backend buffer allocation relative to the effective budget, not all process memory |
| App memory | Process footprint reported by the OS |
| CPU | App CPU time expressed relative to all cores |
| GPU command time | Average elapsed time of completed inference command buffers; includes waits |
| Receive/send | RPC transport bytes per second, including command framing, excluding TCP/IP overhead |
| Graph rate | Remote graph dispatch count per second, not generated tokens per second |
| Thermal state | Apple's nominal/fair/serious/critical pressure category, not degrees Celsius |

The coordinator owns generation timing. GPU command intervals can overlap and do not measure whole-device GPU utilization. Charts retain a clipped recent history and their axes adapt to observed values. Counters describe this worker's session.

## Memory and sustained use

Model tensors, KV cache, recurrent state, scratch buffers, transport staging and the UI all need memory. A buffer budget is not a hard cap on total process RAM. The OS can change available memory and terminate an app under pressure. Keep a reserve and lower the context, batch size or layer allocation when necessary.

The iPad is passively cooled. Use a hard, ventilated surface for sustained measurements and track thermal pressure. Presets express intent; actual speed depends on the model, context, chip, memory pressure, power state and workload.
