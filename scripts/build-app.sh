#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
cache="$PWD/.build/cache"
mkdir -p "$cache" dist
export CLANG_MODULE_CACHE_PATH="$cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache"
swift_options=(--disable-sandbox --cache-path "$cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build "${swift_options[@]}" -c release
bin="$(swift build "${swift_options[@]}" -c release --show-bin-path)/SlowVape"

staging="$(mktemp -d "$PWD/dist/.build-app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Slow Vape.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/SlowVape"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/en.lproj Resources/fr.lproj "$app/Contents/Resources/"
cp Resources/LimitAlert.wav "$app/Contents/Resources/"
cp Resources/SlowVape.icns Resources/BrandMark.png "$app/Contents/Resources/"

xcrun coremlcompiler compile Resources/VapeDetector.mlpackage "$app/Contents/Resources"
cp LICENSE Resources/*-LICENSE.txt "$app/Contents/Resources/"
codesign --force --sign - --entitlements Resources/SlowVape.entitlements "$app"
codesign --verify --strict "$app"
rm -rf "dist/Slow Vape.app"
mv "$app" dist/
printf '%s\n' "$PWD/dist/Slow Vape.app"
