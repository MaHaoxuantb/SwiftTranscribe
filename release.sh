#!/bin/bash
set -euo pipefail

PRODUCT="SwiftTranscribe"
PROFILE="LinecoFlow-Notary-CLT"

# Build Release
xcodebuild \
    -project SwiftTranscribe.xcodeproj \
    -scheme SwiftTranscribe \
    -configuration Release \
    clean build

# Find the produced executable
BUILD_DIR=$(xcodebuild \
    -project SwiftTranscribe.xcodeproj \
    -scheme SwiftTranscribe \
    -configuration Release \
    -showBuildSettings |
    awk '/TARGET_BUILD_DIR/ {print $3; exit}')

BINARY="$BUILD_DIR/$PRODUCT"

# Verify Developer ID signature
codesign --verify --strict --verbose=2 "$BINARY"

# Package it
rm -f "$PRODUCT.zip"
ditto -c -k --keepParent "$BINARY" "$PRODUCT.zip"

# Send to Apple and wait for notarization
xcrun notarytool submit "$PRODUCT.zip" \
    --keychain-profile "$PROFILE" \
    --wait

echo "Release ready: $PRODUCT.zip"
