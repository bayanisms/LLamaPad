# Data and privacy

The source distribution contains no developer account information, personal home paths, machine names, device identifiers, signing profiles, credentials, model weights or recorded user conversations. Build outputs, runtime status snapshots and benchmark logs are excluded.

During use, LlamaPad stores imported models, settings, benchmark records, runtime snapshots and RPC caches in its app container. API keys are stored in Keychain. The chat interface stores conversations in WebKit storage associated with the local server origin. Removing an imported model does not necessarily clear conversations or benchmark history.

Prompts and model data are handled by the local inference server and configured RPC worker. HTTP clients and RPC coordinators can send data over the selected connection. Local-network HTTP is unencrypted, and RPC has no authentication. Prefer the USB loopback tunnel for a directly connected workflow.

The upstream chat UI includes optional external capabilities such as model discovery/downloads, remote endpoints and tool integrations. Using these can contact the selected services and is subject to their policies. A local model does not make every optional integration offline.

Builds contact the npm registry to install pinned chat UI dependencies. xtool and Xcode signing contact Apple when authentication, provisioning or device registration requires it. This release does not include a third-party analytics or crash-reporting SDK in the LlamaPad app code.

Local build and launcher records can include absolute paths, connected-device information and signing identifiers. The app's diagnostic sharing redacts its current API key, but logs can still contain prompts, file paths, addresses or model metadata. Review and redact diagnostics before sharing. Keep generated `build/`, `build-mac/`, `App/xtool/` and signing artifacts out of public repositories.
