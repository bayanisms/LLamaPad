# Troubleshooting

| Symptom | Action |
| --- | --- |
| iOS SDK not found | Install full Xcode, launch it once and select its developer directory. Check `xcrun --sdk iphoneos --show-sdk-path`. |
| xtool reports logged out | Complete `xtool auth login` locally and check `xtool auth status`. Xcode login is separate. |
| Signing/profile rejects memory capability | Inspect the profile and signed entitlements. Use supported Xcode signing, or build with the normal app memory limit and smaller budgets. |
| Installation succeeds but app is untrusted | Enable Developer Mode and trust the developer under the iPad's device-management settings when prompted. |
| Device launch is denied | Unlock the iPad, trust the Mac, check pairing and keep LlamaPad foreground. |
| Source verification reports differences | Confirm the archive is intact. For intentional reviewed edits, regenerate the manifest with `--write-manifest`. |
| Native revision mismatch | Rebuild both app and Mac coordinator from the same source and patch set. |
| Port already in use | Stop the existing owned service/tunnel or choose a different HTTP port. The automatic worker uses RPC port 50052. |
| Model import fails | Check that the file is complete, supported and not a split/model-projector set. Allow room for the imported copy. |
| Model fails to allocate or app is terminated | Lower context, batch, RPC budget or assigned layers. Total process memory exceeds model-buffer allocation. |
| RPC adds latency | Compare local execution when the model fits. Adjust layer placement and measure both GPUs and synchronization. |
| Speed declines during a session | Check thermal pressure, power state and system memory pressure. Use a ventilated surface and repeat sustained measurements. |
| Transfer graph shows small values | Decode traffic can be small after weights are resident. Units adapt through B/s, KiB/s and MiB/s. Graph dispatch is not a token counter. |
| GPU chart does not resemble system utilization | It reports command-buffer elapsed time for this worker, including waits, rather than whole-device utilization. |
| Chat history seems different after changing ports | WebKit storage is associated with the server origin. Use conversation export before changing origins or clearing data. |
| Chat or tool function is unavailable | Check the model's chat template and supported capabilities, plus any configured external integration. |

When sharing a report, include the app version, upstream revision, relevant settings and an anonymized error excerpt. Remove model paths, prompts, API keys, device identifiers, network addresses, account information and signing details. The app's diagnostic sharing redacts its current API key; other sensitive content still needs review.
