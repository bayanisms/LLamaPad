"""Verify or inventory the public source snapshot; uses only the Python standard library."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'SOURCE_MANIFEST.json'
GENERATED = {'.git', '.build', '.swiftpm', '.bsp', 'build', 'build-mac', 'DerivedData',
             'node_modules', 'dist', '.svelte-kit', '__pycache__', 'xcuserdata'}


def source_files():
    for path in sorted(ROOT.rglob('*')):
        relative = path.relative_to(ROOT)
        if any(part in GENERATED for part in relative.parts):
            continue
        if relative.parts[:2] in [('App', 'Frameworks'), ('App', 'xtool')]:
            continue
        if path.name in {'SOURCE_MANIFEST.json', '.DS_Store'}:
            continue
        if path.is_symlink():
            raise SystemExit(f'Symbolic link cannot be inventoried: {relative}')
        if path.is_file():
            yield relative.as_posix(), path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-only', action='store_true')
    parser.add_argument('--write-manifest', action='store_true')
    args = parser.parse_args()
    if args.write_manifest:
        files = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in source_files()}
        MANIFEST.write_text(json.dumps({'format': 1, 'hash': 'sha256',
            'upstream_revision': (ROOT / 'upstream.lock').read_text().strip(), 'files': files}, indent=2) + '\n')
        print(f'Inventoried {len(files)} source files.')
        return
    data = json.loads(MANIFEST.read_text())
    revision = (ROOT / 'upstream.lock').read_text().strip()
    if data['upstream_revision'] != revision:
        raise SystemExit('Engine revision does not match the source inventory.')
    checked = 0
    failures = []
    for name, expected in data['files'].items():
        if args.engine_only and not name.startswith('vendor/llama.cpp/'):
            continue
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise SystemExit('Invalid manifest path.')
        path = ROOT / relative
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            failures.append(name)
        checked += 1
    if failures:
        print('\n'.join(f'Missing or modified: {name}' for name in failures))
        raise SystemExit('Source differs from the inventory. Review intentional edits before regenerating it.')
    print(f'Verified {checked} source files; engine {revision[:12]}.')


if __name__ == '__main__':
    main()
