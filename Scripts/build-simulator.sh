#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash Scripts/fetch-upstream.sh
# Keep both packaged slices on the same pinned source and native bridge.
bash Scripts/build-ios.sh
cmake -S . -B build/ios-simulator -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON
cmake --build build/ios-simulator --target llamapad-native --parallel "${JOBS:-3}"
mkdir -p build/ios-simulator-package
xcrun libtool -static -o build/ios-simulator-package/libLlamaNative.a -filelist build/ios-simulator/llamapad-archives.txt
framework_dir="$(mktemp -d "$project_dir/build/ios-simulator-package/framework.XXXXXX")"
trap 'rm -rf "$framework_dir"' EXIT
xcodebuild -create-xcframework \
    -library "$project_dir/build/ios-package/libLlamaNative.a" -headers "$project_dir/Native/include" \
    -library "$project_dir/build/ios-simulator-package/libLlamaNative.a" -headers "$project_dir/Native/include" \
    -output "$framework_dir/LlamaNative.xcframework"
python3 - "$framework_dir/LlamaNative.xcframework" <<'PY'
from pathlib import Path
import shutil, sys
destination = Path('App/Frameworks/LlamaNative.xcframework')
shutil.rmtree(destination)
shutil.move(sys.argv[1], destination)
PY
(
    cd App
    xtool dev generate-xcode-project
)
python3 Scripts/configure-xcode.py
xcodebuild -workspace App/xtool/LlamaPad.xcworkspace -scheme LlamaPad-App \
    -configuration Debug -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/xcode-simulator ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual ALWAYS_SEARCH_USER_PATHS=NO build
