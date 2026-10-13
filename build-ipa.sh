#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate --spec project.yml
SOLO_BUILD_DIR="${SOLO_BUILD_DIR:-/private/tmp/solo-phone-release}"
xcodebuild -project SoloPocket.xcodeproj -scheme SoloPocket -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$SOLO_BUILD_DIR" \
  -clonedSourcePackagesDirPath /private/tmp/solo-phone-packages \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
SOLO_STAGE_DIR=$(mktemp -d /private/tmp/solo-pocket-ipa.XXXXXX)
trap 'rm -rf "$SOLO_STAGE_DIR"' EXIT
mkdir -p "$SOLO_STAGE_DIR/Payload" dist
ditto --norsrc --noextattr "$SOLO_BUILD_DIR/Build/Products/Release-iphoneos/SoloPocket.app" "$SOLO_STAGE_DIR/Payload/SoloPocket.app"
ditto -c -k --norsrc --noextattr --keepParent "$SOLO_STAGE_DIR/Payload" "$SOLO_STAGE_DIR/SoloPocket.ipa"
python3 tools/validate_ipa.py "$SOLO_STAGE_DIR/SoloPocket.ipa"
mv "$SOLO_STAGE_DIR/SoloPocket.ipa" dist/SoloPocket.ipa
shasum -a 256 dist/SoloPocket.ipa > dist/SoloPocket.ipa.sha256
SOLO_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SOLO_STAGE_DIR/Payload/SoloPocket.app/Info.plist")
cp dist/SoloPocket.ipa "dist/SoloPocket-$SOLO_VERSION.ipa"
shasum -a 256 "dist/SoloPocket-$SOLO_VERSION.ipa" > "dist/SoloPocket-$SOLO_VERSION.ipa.sha256"
echo "AltStore 安装包已保存：$(pwd)/dist/SoloPocket.ipa"
