# LlamaPad

Run GGUF models on an Apple M-series iPad, or use the iPad as a Metal RPC worker for a Mac running the matching llama.cpp engine.

<img src="App/Artwork/AppIcon.png" width="160" alt="A llama wearing sunglasses and holding a tablet">

LlamaPad has separate **Inference Server** and **RPC Node** workspaces. The inference workspace includes the embedded llama.cpp chat interface, model settings and connection controls. The RPC workspace includes worker controls and live memory, transfer, CPU, GPU-command timing and thermal-pressure charts. Models can be imported through Files or Finder file sharing.

This is a development source release, version **0.3.2**. It targets stock iPadOS 18 or later on Apple M-series iPads, with device-dependent runtime tuning. Other chips have not been qualified by this release. The app must remain in the foreground. Installation requires signing with your own Apple developer account; increased-memory access depends on provisioning and the operating system.

## Included source

The native engine and chat UI source are vendored in `vendor/llama.cpp`. The pinned upstream revision is recorded in [upstream.lock](upstream.lock). The current LlamaPad engine modifications are included both in that source and in [patches/0001-llamapad-engine.patch](patches/0001-llamapad-engine.patch). Source archives build without a nested Git checkout.

The package contains no model weights, test suites, build products, signed applications, provisioning profiles, device records or benchmark logs. Model licenses and compatibility must be checked separately.

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
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Data storage and privacy](PRIVACY.md)
- [Security considerations](SECURITY.md)
- [Release notes](CHANGELOG.md) and [publishing instructions](docs/RELEASING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

LlamaPad's original code is MIT licensed; bundled components retain their own notices. This project is independent of Apple and the llama.cpp project.
