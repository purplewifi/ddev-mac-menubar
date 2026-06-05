#!/usr/bin/env bash
set -euo pipefail

# Sign a Developer ID exported .app for notarization, including Sparkle's
# nested helpers. Sparkle must be signed innermost-first; never use --deep.

APP="${1:?Usage: sign-app-for-release.sh /path/to/App.app [keychain-path]}"
KEYCHAIN="${2:-}"

sign() {
  local target="$1"
  shift
  echo "  signing: $target"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@" "$target"
}

if [ -n "$KEYCHAIN" ]; then
  IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" \
    | grep "Developer ID Application" | head -1 | awk '{print $2}')
else
  IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | awk '{print $2}')
fi

if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application identity found" >&2
  exit 1
fi

echo "Signing with: $IDENTITY"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_B="$SPARKLE/Versions/B"

if [ -d "$SPARKLE" ]; then
  # Clear the app seal before re-signing nested Sparkle helpers.
  rm -rf "$APP/Contents/_CodeSignature"

  for xpc in "$SPARKLE_B"/XPCServices/*.xpc; do
    [ -e "$xpc" ] || continue
    if [[ "$(basename "$xpc")" == "Downloader.xpc" ]]; then
      sign "$xpc" --preserve-metadata=entitlements
    else
      sign "$xpc"
    fi
  done

  sign "$SPARKLE_B/Autoupdate"

  if [ -d "$SPARKLE_B/Updater.app" ]; then
    sign "$SPARKLE_B/Updater.app"
  fi

  sign "$SPARKLE"
fi

sign "$APP"

codesign --verify --strict --verbose=2 "$APP"
