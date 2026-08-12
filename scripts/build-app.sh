#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Pi.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Pi" "$app_dir/Contents/MacOS/Pi"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

echo "Built $app_dir"
echo "Open with: open $app_dir"

