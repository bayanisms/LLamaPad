# LlamaPad

Run GGUF models on an Apple M-series iPad, or use the iPad as a Metal RPC worker for a Mac running the matching llama.cpp engine.

<img src="App/Artwork/AppIcon.png" width="160" alt="A llama wearing sunglasses and holding a tablet">

LlamaPad has separate **Inference Server** and **RPC Node** workspaces. The inference workspace includes the embedded llama.cpp chat interface, model settings and connection controls. The RPC workspace includes worker controls and live memory, transfer, CPU, GPU-command timing and thermal-pressure charts. Models can be imported through Files or Finder file sharing.

This is a development source release, version **0.3.2**. It targets stock iPadOS 18 or later on Apple M-series iPads, with device-dependent runtime tuning. Other chips have not been qualified by this release. The app must remain in the foreground. Installation requires signing with your own Apple developer account; increased-memory access depends on provisioning and the operating system.

## Measured performance

The recorded hardware is an **M1 Pro Mac with 16 GiB RAM and an M1 iPad with 16 GiB RAM**. These are local measurements on that pair, not results for the base M1 Mac or every M-series device. Rates below are pooled **generation tokens/s**, with startup and warmup excluded.

### What the iPad adds

| Model / configuration | Mac alone | Mac + iPad RPC | Observed value |
| --- | ---: | ---: | --- |
| LFM2.5-24B-A2B Q4_K_M, ordinary chat | 4.47 | **29.59** | **6.62x throughput** versus the tested 8 GiB Mac expert-cache configuration; six matched replies per mode |
| Qwen3.6-27B Q4_K_M, native-MTP-preserved variant | Memory guard stopped startup; no completed rate | 3.56 ordinary / **8.15 with MTP4** | Runs within the tested Mac memory budget; no Mac-only speedup ratio is claimed |

The LFM comparison uses the same weights and prompts, a 2,048-token context capacity, no speculation, and a 70/30 Mac/iPad split. The Mac-only case uses six CPU threads and an 8 GiB GPU expert cache; RPC uses two coordinator threads. All six returned texts match. The benefit is avoiding the tested single-device memory bottleneck. Qwen has eight completed replies per successful method; thermal behavior affects its measured rates.

This comparison focuses on models that exceed the tested Mac memory budget. Moving weights onto the iPad can also leave more Mac memory for KV/recurrent state and runtime buffers. Larger contexts and higher-precision quants are potential uses of that capacity; their performance and maximum supported context have not yet been measured here.

### Improvements retained in LlamaPad

Separate control/candidate/candidate/control comparisons on the same LFM Q4_K_M weights measured:

| Change and workload | Control | Selected | Generation change | Paired outputs |
| --- | ---: | ---: | ---: | --- |
| Router + gated-convolution fusions and GPU submission tuning, Mac + iPad | 29.11 | **30.11** | **+3.46%** | 12/12 identical |
| Canonical replay + 26-token n-gram drafting versus the prior eight-token preset, full suite | 35.89 | **37.61** | **+4.79%** | 24/24 identical |
| Same replay/drafting comparison, editing subset | 38.49 | **41.57** | **+7.98%** | 14/14 identical |

The editing row is a subset of the full suite, not a separate additive gain. In that same replay comparison, fresh chat changed from 30.25 to 29.79 tokens/s (**-1.53%**). The replay change is in the Mac coordinator; the fusion/submission comparison enables changes on both GPUs. These experiments do not establish separate Mac-only or iPad-only engine speedups. Exact output agreement covers the measured greedy requests, not every prompt or sampler.

The later 55/45 split reduces Mac model-buffer allocation by **2.04 GiB** versus the earlier 70/30 placement. That is allocation saved, not a guarantee of 2 GiB physically free RAM. Experimental settings are opt-in; the results are not default-app guarantees, and ordinary 24B chat has not reached 60 tokens/s.

See [benchmark methods, settings and limitations](docs/BENCHMARKS.md) and [sanitized timing/output-hash data](docs/benchmark-results.json). The comparisons are separate experiments; their speedups must not be multiplied together.

## Included source

The native engine and chat UI source are vendored in `vendor/llama.cpp`. The pinned upstream revision is recorded in [upstream.lock](upstream.lock). The current LlamaPad engine modifications are included both in that source and in [patches/0001-llamapad-engine.patch](patches/0001-llamapad-engine.patch). Source archives build without a nested Git checkout.

The package contains no model weights, test suites, build products, signed applications, provisioning profiles, device records or raw benchmark logs. The benchmark documentation contains only sanitized results. Model licenses and compatibility must be checked separately.

## Build and install

You need an Apple Silicon Mac, full Xcode with an iOS SDK, CMake 3.24 or later, Python 3, Node.js 22.12 or later in the 22 series (or a newer compatible release), npm, and [xtool](https://github.com/xtool-org/xtool). Install `libusbmuxd` for the `iproxy` USB tunnel. Choose an Xcode release compatible with your macOS and iPadOS.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk iphoneos --show-sdk-path
python3 Scripts/verify-source.py
bash Scripts/build-ios.sh
```

Sign in to Apple locally, then install using xtool:

```sh
xtool setup
xtool auth login
cd App
xtool dev run --configuration release --usb
```

For Xcode automatic signing instead, return to the repository root and run:

```sh
bash Scripts/install-ios.sh TEAM_ID DEVICE_UDID
```

Replace the placeholders with your own values. Connect and unlock the iPad, trust the Mac, enable Developer Mode, and trust the developer certificate when prompted. The default bundle identifier is `dev.local.LlamaPad`; see [building](docs/BUILDING.md) before changing it.

## Inference server

Import a compatible GGUF in **Models**, select it, and start **Inference Server**. The Chat section uses the embedded UI. To connect a Mac client through USB:

```sh
iproxy --local 8080:8080
export LLAMAPAD_API_KEY='PASTE_THE_KEY_SHOWN_IN_THE_APP'
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $LLAMAPAD_API_KEY" \
  -d '{"model":"llamapad","messages":[{"role":"user","content":"Hello"}],"max_tokens":128}'
```

Use the model alias displayed in the app if it differs from `llamapad`. API keys are stored in Keychain. Local-network mode uses plain HTTP and requires a key; use a trusted network.

## Mac with an iPad RPC worker

Build the matching coordinator:

```sh
bash Scripts/build-mac.sh
python3 Scripts/run-rpc.py /path/to/model.gguf \
  --device DEVICE_UDID --ipad-first --split 40,60
```

Keep LlamaPad open on the connected iPad. The launcher starts its RPC worker and USB tunnel, then serves the Mac API at `http://127.0.0.1:8080/v1`. The split is expressed as **Mac,iPad** proportions. It is a starting capacity setting, not a universal performance recommendation. Ctrl-C stops the coordinator and tunnel.

For a manually started worker, select **RPC Node** in the app, start it, then use separate terminals:

```sh
iproxy --local 50052:50052
```

```sh
./build-mac/bin/llama-server -m /path/to/model.gguf \
  --rpc 127.0.0.1:50052 --split-mode layer -ngl 999 -c 2048
```

RPC provides additional model capacity. Sequential layer execution and transport can make it slower than a model that already fits locally. RPC has no authentication; keep it on the USB loopback tunnel or a trusted isolated network. The Mac launcher's HTTP API binds to loopback and has no API key.

## Documentation

- [Build, signing and simulator instructions](docs/BUILDING.md)
- [Inference and RPC usage](docs/USAGE.md)
- [Architecture and source layout](docs/ARCHITECTURE.md)
- [Engine changes and performance tuning](docs/ENGINE.md)
- [Measured benchmarks and methodology](docs/BENCHMARKS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Data storage and privacy](PRIVACY.md)
- [Security considerations](SECURITY.md)
- [Release notes](CHANGELOG.md) and [publishing instructions](docs/RELEASING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

LlamaPad's original code is MIT licensed; bundled components retain their own notices. This project is independent of Apple and the llama.cpp project.
