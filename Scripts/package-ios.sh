#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_dir/build/xcode-device/Build/Products/Release-iphoneos/LlamaPad-App.app}"
codesign --verify --deep --strict "$app_path"
package_dir="$(mktemp -d "$project_dir/build/ipa-package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
mkdir "$package_dir/Payload"
ditto "$app_path" "$package_dir/Payload/LlamaPad.app"
ditto -c -k --sequesterRsrc --keepParent "$package_dir/Payload" "$project_dir/build/LlamaPad.ipa"
unzip -tq "$project_dir/build/LlamaPad.ipa"
echo "Signed app packaged at $project_dir/build/LlamaPad.ipa"
