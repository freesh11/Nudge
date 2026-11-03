#!/bin/bash
# Builds an UNSIGNED Nudge.ipa (needs macOS + Xcode). Sign it afterwards with your KravaSign cert.
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

xcodebuild -project Nudge.xcodeproj -target Nudge -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ${MARKETING_VERSION:+MARKETING_VERSION=$MARKETING_VERSION} \
  ${CURRENT_PROJECT_VERSION:+CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION} build

app="build/Release-iphoneos/Nudge.app"
test -d "$app/PlugIns/NudgeWidget.appex" || { echo "Widget missing from the app bundle"; exit 1; }
test -f "$app/Assets.car" || { echo "App icon missing from the app bundle"; exit 1; }
plutil -p "$app/Info.plist" | grep -q "AppIcon-mint" || { echo "Alternate icons missing from Info.plist"; exit 1; }

echo "Version $(plutil -extract CFBundleShortVersionString raw "$app/Info.plist") (build $(plutil -extract CFBundleVersion raw "$app/Info.plist"))"

rm -rf Payload Nudge.ipa
mkdir Payload
cp -R "$app" Payload/
zip -qry Nudge.ipa Payload
rm -rf Payload
echo "Built $(pwd)/Nudge.ipa"
