#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if [ "$#" -eq 2 ]; then
    signing_team="$1"
    device_udid="$2"
elif [ "$#" -eq 0 ] && [ -f build/device-signing.json ]; then
    read -r signing_team device_udid < <(python3 - <<'PY'
import json
from pathlib import Path
settings = json.loads(Path('build/device-signing.json').read_text())
print(settings['team'], settings['device'])
PY
    )
else
    echo 'Usage: bash Scripts/install-ios.sh TEAM_ID DEVICE_UDID' >&2
    echo 'Or omit arguments to reuse build/device-signing.json on this Mac.' >&2
    exit 1
fi
if [[ ! "$signing_team" =~ ^[A-Z0-9]{10}$ ]] || [[ ! "$device_udid" =~ ^[A-Fa-f0-9-]+$ ]]; then
    echo 'Invalid signing team or device UDID.' >&2
    exit 1
fi

bash Scripts/build-ios.sh
(
    cd App
    xtool dev generate-xcode-project
)
python3 Scripts/configure-xcode.py
xcodebuild -workspace App/xtool/LlamaPad.xcworkspace -scheme LlamaPad-App \
    -configuration Release -destination "id=$device_udid" \
    -derivedDataPath build/xcode-device \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "DEVELOPMENT_TEAM=$signing_team" CODE_SIGN_STYLE=Automatic ALWAYS_SEARCH_USER_PATHS=NO build

app_path="$project_dir/build/xcode-device/Build/Products/Release-iphoneos/LlamaPad-App.app"
xcrun devicectl device install app --device "$device_udid" "$app_path" --timeout 120
bash Scripts/package-ios.sh "$app_path"
python3 - "$signing_team" "$device_udid" <<'PY'
import json, sys
from pathlib import Path
# Device/team identifiers only; no credentials or signing keys.
Path('build/device-signing.json').write_text(json.dumps({'team': sys.argv[1], 'device': sys.argv[2]}, indent=2))
PY
echo 'Installed LlamaPad. Open it on the iPad; trust the developer in Settings if prompted.'
