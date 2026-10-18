#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    echo 'iOS SDK missing. Install a full Xcode version compatible with your macOS and launch it once.' >&2
    echo 'Then set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer and rerun this script.' >&2
    exit 1
fi
bash Scripts/fetch-upstream.sh
bash Scripts/build-chat-ui.sh
cmake -S . -B build/ios-arm64 \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON
cmake --build build/ios-arm64 --target llamapad-native --parallel "${JOBS:-4}"
mkdir -p build/ios-package App/Frameworks
xcrun libtool -static -o build/ios-package/libLlamaNative.a -filelist build/ios-arm64/llamapad-archives.txt
# xcodebuild refuses an existing output. Preserve it until the replacement is complete.
package_dir="$(mktemp -d "$project_dir/build/ios-package/xcframework.XXXXXX")"
xcodebuild -create-xcframework -library "$project_dir/build/ios-package/libLlamaNative.a" \
    -headers "$project_dir/Native/include" -output "$package_dir/LlamaNative.xcframework"
python3 - "$package_dir/LlamaNative.xcframework" <<'PY'
from pathlib import Path
import shutil, sys
destination = Path('App/Frameworks/LlamaNative.xcframework')
if destination.exists():
    shutil.rmtree(destination)
shutil.move(sys.argv[1], destination)
PY
cd App
xtool dev build --configuration release
