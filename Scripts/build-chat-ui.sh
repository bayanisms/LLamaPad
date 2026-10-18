#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
source_dir="$project_dir/vendor/llama.cpp/tools/ui"
work_dir="$project_dir/build/chat-ui-source"
stamp="$(cat upstream.lock)-$(shasum -a 256 App/ChatUI/* App/Artwork/AppIcon.png Scripts/build-chat-ui.sh | shasum -a 256 | cut -d ' ' -f 1)"
if [ -f "$source_dir/dist/llamapad-build.txt" ] && [ "$(cat "$source_dir/dist/llamapad-build.txt")" = "$stamp" ]; then
    exit 0
fi
mkdir -p "$work_dir"
rsync -a --exclude=node_modules --exclude=dist --exclude=.svelte-kit "$source_dir/" "$work_dir/"
cp "$project_dir/App/ChatUI/Logo.svelte" "$work_dir/src/lib/components/app/misc/Logo.svelte"
cat "$project_dir/App/ChatUI/theme.css" >> "$work_dir/src/app.css"
# Use the app icon inside the chat workspace as well.
cp "$project_dir/App/Artwork/AppIcon.png" "$work_dir/static/llamapad.png"
python3 - "$work_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
path = root / 'src/app.html' 
s = path.read_text().replace('href="favicon.svg"', 'href="llamapad.png"').replace('type="image/svg+xml"', 'type="image/png"')
path.write_text(s)
# The embedded UI ships with the app. Browser clients retain normal PWA updates.
pwa = root / 'src/lib/hooks/use-pwa.svelte.ts'
s = pwa.read_text().replace("import { browser }", "import { writable } from 'svelte/store';\nimport { browser }", 1)
s = s.replace('export function usePwa() {', """export function usePwa() {
    if (browser && '__LLAMAPAD_NATIVE__' in window) {
        const needRefresh = writable(false);
        return { get needRefresh() { return needRefresh; }, get needRefreshByStorage() { return false; }, updateServiceWorker: async () => {} };
    }
""")
pwa.write_text(s)
settings = root / 'src/lib/constants/settings.constants.ts'
s = settings.read_text().replace('help: `Set the API Key if you are using <code> ${CLI_FLAGS.API_KEY} </code> option for the server.`', "help: 'LlamaPad authenticates built-in chat automatically. In an external browser, enter the key from the server Settings tab.'")
settings.write_text(s)
PY
cd "$work_dir"
npm ci --no-audit --no-fund
LLAMA_BUILD_NUMBER="$(head -c 12 "$project_dir/upstream.lock")" npm run build
printf '%s' "$stamp" > dist/llamapad-build.txt
mkdir -p "$source_dir/dist"
rsync -a --delete dist/ "$source_dir/dist/"
