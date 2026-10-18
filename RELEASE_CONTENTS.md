# Source-package checks

This source snapshot includes the SwiftUI app, Core module, C/Objective-C++ bridge, artwork, chat UI source, vendored engine, retained engine patches, build/install/launch scripts and public documentation.

The following checks were completed on the prepared source folder:

- Swift Core module build.
- Production embedded chat UI build from the included source and pinned npm lockfile.
- CMake configuration for the Mac coordinator and ARM64 iOS native targets.
- Python and shell script syntax checks.
- Reconstruction of modified engine files by applying the two included patches to the pinned upstream revision.
- SHA-256 inventory verification and checks that all release files are visible to a new Git repository's ignore rules.
- Scans for personal home paths, known private identifiers, credentials, excluded artifacts and test-suite paths.
- Removal of PNG text, EXIF and timestamp metadata while preserving image pixel data.
- ZIP entry/content verification using relative paths, fixed timestamps and standard permissions.

These checks do not constitute a fresh signed device installation or a complete correctness/security audit. Runtime performance and model compatibility require validation on the intended devices. The source manifest and ZIP checksum provide file integrity; they are not publisher signatures.

No tests, model weights, private benchmark records, raw runtime logs, Git history, compiled application/native libraries, signing credentials, provisioning profiles, device records or computer-specific configuration are distributed. The benchmark documentation includes only sanitized settings, measurements and returned-output hashes. Public third-party copyright and author notices remain intact.
