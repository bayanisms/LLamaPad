# Building LlamaPad

## Requirements

- An Apple Silicon Mac with full Xcode installed, including a physical-device iOS SDK. Command Line Tools alone are insufficient.
- An Xcode/macOS combination supported by Apple and compatible with the connected iPadOS version.
- CMake 3.24 or later, Python 3, Node.js 22.12 or later in the 22 series (or a newer release supported by Vite), and npm.
- xtool for Swift-package application generation and packaging.
- `libusbmuxd` providing `iproxy` for USB RPC.
- An Apple account for local development signing. Free and paid accounts have different provisioning and renewal limits.

Apple's Xcode and SDK license terms apply. This source release does not include an SDK or signing material.

## Verify the source archive

```sh
python3 Scripts/verify-source.py
```

This compares included files with `SOURCE_MANIFEST.json`. `Scripts/fetch-upstream.sh` retains its historical name but now verifies the included engine instead of cloning or resetting a checkout. The app and Mac coordinator must use the same revision and LlamaPad engine changes.

Intentional source edits invalidate the manifest. After reviewing your edits, regenerate it with `python3 Scripts/verify-source.py --write-manifest`. Keep the resulting manifest in your own source revision. The manifest is an integrity inventory, not a cryptographic signature from a publisher.

## Physical iPad build

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk iphoneos --show-sdk-path
bash Scripts/build-ios.sh
```

The script verifies the engine, builds the chat UI using `npm ci`, cross-compiles the native ARM64 libraries in Release mode, creates `App/Frameworks/LlamaNative.xcframework`, and invokes xtool. Native Metal source is embedded for compilation on the device. The CPU baseline uses instructions shared by M-series processors; GPU dispatch retains upstream capability checks.

The first UI build needs network access to the npm registry. The lockfile pins dependency versions and integrity hashes. No prebuilt UI is downloaded from a model host. Native source is already included.

Use `JOBS=2 bash Scripts/build-ios.sh` to reduce concurrent compiler memory use. This setting affects build concurrency, not inference speed.

## Sign and install

Authenticate locally with `xtool setup` and, if needed, `xtool auth login`. Check `xtool auth status`; Xcode's account settings are separate from xtool authentication. From `App`, run `xtool dev run --configuration release --usb`.

Alternatively, configure your account in Xcode and run from the repository root:

```sh
bash Scripts/install-ios.sh TEAM_ID DEVICE_UDID
```

The script generates the Xcode workspace, attaches the icon catalog, builds with automatic signing, installs with `devicectl`, and creates `build/LlamaPad.ipa`. It saves your team/device identifiers in the ignored local file `build/device-signing.json` for subsequent installations. These generated records and signed files are private build outputs and should stay out of source releases.

Use `xcrun devicectl list devices` to find your connected device identifier. Keep account credentials in Apple's or xtool's local authentication workflow.

The app requests `com.apple.developer.kernel.increased-memory-limit`. Its availability depends on the signing profile, device and OS. Inspect your signed app's entitlements with `codesign -d --entitlements :- /path/to/LlamaPad.app`. If your provisioning cannot permit the entitlement, remove `entitlementsPath` from `App/xtool.yml` for a build with the standard app memory limit and use smaller models/budgets.

Before your first installation, choose a unique bundle identifier if needed. Update `App/xtool.yml`; pass the same identifier to the automatic launcher with `--bundle-id YOUR_BUNDLE_IDENTIFIER`. Keychain and app data are associated with the application identity. The display name can remain LlamaPad.

## Mac coordinator

```sh
bash Scripts/build-mac.sh
./build-mac/bin/llama-server --version
./build-mac/bin/llama-server --list-devices
```

The archive passes the pinned engine revision into CMake explicitly so version matching works without Git history. The build produces `llama-server` and upstream `llama-bench`; no test executable is built. The Mac coordinator uses the upstream CLI and local Metal backend plus RPC.

## ARM64 simulator

```sh
bash Scripts/build-simulator.sh
```

This builds both native slices, regenerates the XCFramework and produces a simulator app under `build/xcode-simulator`. It requires the matching simulator runtime in Xcode. Simulator behavior does not establish physical-device memory capacity or performance. No UI test target is generated.

## Useful outputs

| Path | Purpose |
| --- | --- |
| `App/Frameworks/LlamaNative.xcframework` | Generated native library used by Swift Package Manager |
| `App/xtool/` | Generated application and Xcode workspace |
| `build/ios-arm64/` | Physical-device native build |
| `build/chat-ui-source/` | UI build workspace and npm dependencies |
| `build/xcode-device/` | Locally signed Xcode build |
| `build-mac/bin/` | Coordinator and native libraries |

These outputs are excluded by `.gitignore`. Publish the source archive separately from any intentionally distributed, appropriately signed application.
