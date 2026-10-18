# Third-party notices

The root MIT license applies to original LlamaPad code. Upstream code and bundled dependencies retain their copyright and license notices. Do not remove source headers or the license files supplied below.

| Component | Location | License / notice |
| --- | --- | --- |
| llama.cpp / GGML and upstream chat UI | `vendor/llama.cpp` | MIT, `vendor/llama.cpp/LICENSE`; individual files may include additional notices |
| nlohmann/json | `vendor/llama.cpp/vendor/nlohmann` | MIT, `vendor/llama.cpp/licenses/LICENSE-jsonhpp` and source headers |
| cpp-httplib | `vendor/llama.cpp/vendor/cpp-httplib` | MIT, bundled `LICENSE` |
| hash implementations | `vendor/llama.cpp/vendor/hash` | Preserve the SHA-256, xxHash and rotate-bits license files and source notices |
| miniaudio and other header-only code | `vendor/llama.cpp/vendor` | Terms appear in the corresponding source headers/files |
| big-integer | `vendor/llama.cpp/tools/ui/src/lib/vendors/big-integer` | Bundled `LICENSE` |
| nerdamer-prime | `vendor/llama.cpp/tools/ui/src/lib/vendors/nerdamer-prime` | Bundled `LICENSE` |
| npm dependencies | `vendor/llama.cpp/tools/ui/package-lock.json` | Per-package terms; see `DEPENDENCIES.json` for a lockfile-derived inventory |

The dependency inventory records package names, versions and license expressions available in the lockfile. Some packages have incomplete metadata; the actual package license files govern. The inventory includes transitive build dependencies and is not a claim that every listed package is shipped in the runtime. Test tooling may remain in the upstream dependency lockfile to preserve installation integrity; test suites and test targets are excluded from the source package.

When distributing compiled chat UI assets or binaries, preserve the notices required by the dependencies actually included. Inspect installed package license files and multi-license choices, including permissive alternatives where available. Model weights are not included and have separate licenses selected by their owners. Xcode, Apple SDKs, xtool, and libusbmuxd are separately installed tools and are not redistributed here.

The LlamaPad icon/brand artwork was generated for this project with an image-generation tool. The distributed PNGs contain the artwork without text, EXIF or timestamp metadata. No claim of affiliation with Apple or the upstream engine project is made.
