#!/bin/bash
set -euo pipefail

PRODUCT="SwiftTranscribe"
PROFILE="LinecoFlow-Notary-CLT"
IDENTITY="Developer ID Application: LinecoFlow LLC (832FW23SZD)"

echo "Building Release..."

xcodebuild \
    -project SwiftTranscribe.xcodeproj \
    -scheme SwiftTranscribe \
    -configuration Release \
    clean build

# Find produced executable
BUILD_DIR=$(xcodebuild \
    -project SwiftTranscribe.xcodeproj \
    -scheme SwiftTranscribe \
    -configuration Release \
    -showBuildSettings |
    awk '/TARGET_BUILD_DIR/ {print $3; exit}')

BINARY="$BUILD_DIR/$PRODUCT"

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found: $BINARY"
    exit 1
fi

echo "Re-signing for distribution..."

codesign \
    --force \
    --sign "$IDENTITY" \
    --options runtime \
    --timestamp \
    "$BINARY"

echo "Verifying signature..."

codesign --verify \
    --strict \
    --verbose=2 \
    "$BINARY"

codesign -dv --verbose=4 "$BINARY"

echo "Checking entitlements..."
codesign -d --entitlements :- "$BINARY" || true

echo "Packaging..."

rm -f "$PRODUCT.zip"

ditto \
    -c \
    -k \
    --keepParent \
    "$BINARY" \
    "$PRODUCT.zip"

echo "Submitting to Apple for notarization..."

RESULT=$(xcrun notarytool submit "$PRODUCT.zip" \
    --keychain-profile "$PROFILE" \
    --wait \
    --output-format json)

echo "$RESULT"

STATUS=$(printf '%s' "$RESULT" |
    plutil -extract status raw -o - -)

SUBMISSION_ID=$(printf '%s' "$RESULT" |
    plutil -extract id raw -o - -)

if [[ "$STATUS" != "Accepted" ]]; then
    echo "ERROR: Notarization failed with status: $STATUS"
    echo "Fetching Apple's notarization log..."

    xcrun notarytool log "$SUBMISSION_ID" \
        --keychain-profile "$PROFILE"

    exit 1
fi

echo
echo "Notarization accepted."
echo "Release ready: $PRODUCT.zip"
