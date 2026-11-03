#!/bin/bash
# Builds an UNSIGNED Nudge.ipa (needs macOS + Xcode). Sign it afterwards with your KravaSign cert.
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

xcodebuild -project Nudge.xcodeproj -target Nudge -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

app="build/Release-iphoneos/Nudge.app"
test -d "$app/PlugIns/NudgeWidget.appex" || { echo "Widget missing from the app bundle"; exit 1; }

rm -rf Payload Nudge.ipa
mkdir Payload
cp -R "$app" Payload/
zip -qry Nudge.ipa Payload
rm -rf Payload
echo "Built $(pwd)/Nudge.ipa"
