# Publishing a source release

This folder is the repository root. It contains source and public documentation and can be uploaded to a new GitHub repository. Publishing is a separate action performed by the repository owner.

## Before publishing

1. Confirm the project license and retain all bundled third-party notices.
2. Review the version in `App/Info.plist` and release notes in `CHANGELOG.md`.
3. Run `python3 Scripts/verify-source.py`. After intentional edits, review the diff and regenerate the manifest with `--write-manifest` before checking it again.
4. Build the native/app targets with the intended toolchain and inspect the application on your own device. Keep build logs local.
5. Confirm no model files, test suites, signed apps, private logs, caches, local environment files, profiles, certificates or Git history have been added.
6. Create a repository under the owner/name of your choice and upload the source. Enable private vulnerability reporting if desired.

The prepared folder has no Git history or remote attached. GitHub's web upload or a local repository initialized by the owner can be used. Review the staged files before the first commit. `.gitignore` excludes generated directories and common private artifacts.

## Release assets

Use a version tag corresponding to the source and create a GitHub Release with `CHANGELOG.md` as the basis for the description. A source ZIP and SHA-256 checksum can be attached. The prepared ZIP contains only this source snapshot; its checksum is beside the archive.

If packaging again after building, use the manifest to select only release files rather than archiving the entire working directory. For example, run from the repository root:

```sh
python3 Scripts/verify-source.py
python3 - <<'PY'
import hashlib
import json
from pathlib import Path
import zipfile

root = Path.cwd()
manifest = json.loads((root / 'SOURCE_MANIFEST.json').read_text())
archive = root.parent / 'LlamaPad-source.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
    for name in sorted([*manifest['files'], 'SOURCE_MANIFEST.json']):
        info = zipfile.ZipInfo('LlamaPad/' + name, (2026, 1, 1, 0, 0, 0))
        info.create_system = 3
        mode = 0o755 if (root / name).stat().st_mode & 0o111 else 0o644
        info.external_attr = (0o100000 | mode) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        output.writestr(info, (root / name).read_bytes())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
PY
```

The archive uses relative paths, fixed timestamps and standard permissions, with no owner IDs, filesystem attributes or original modification times. Verify the ZIP's entries and content before publishing. The checksum establishes file identity, not publisher authenticity; use your own release-signing process if required.

Signed IPA files embed signing/provisioning metadata and can be restricted to enrolled devices. They require a separate, deliberate distribution process and are excluded from this source release. Review dependency license obligations for any compiled distribution, including npm packages linked into the chat UI. `THIRD_PARTY_NOTICES.md` and the lockfile inventory provide starting points.
