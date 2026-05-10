#!/usr/bin/env bash
#
# Build, sign, and install a local prod (Release) macshot from `main`.
#
# Uses your Apple Development identity so the codesign designated requirement
# stays stable across rebuilds — TCC permissions (Screen Recording,
# Accessibility) granted once will keep working.
#
# Strips Sparkle's auto-update feed from Info.plist so the installed build
# never offers to overwrite itself with the upstream sw33tLie release.
#
# Usage:
#   scripts/build-local-prod.sh             # pulls main, builds, installs, launches
#   scripts/build-local-prod.sh --no-pull   # build current checkout as-is
#   scripts/build-local-prod.sh --reset-tcc # also reset TCC grants (forces re-prompt once)
#
# Override the signing identity via env var:
#   MACSHOT_SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-local-prod.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/macshot.xcodeproj"
ENTITLEMENTS_FILE="$PROJECT_DIR/macshot/macshot.entitlements"
BUILD_DIR="$PROJECT_DIR/build/local-prod"
APP_OUT="$BUILD_DIR/Build/Products/Release/macshot.app"
INSTALL_PATH="/Applications/macshot.app"

# Pick the first Apple Development identity by default. Override with MACSHOT_SIGN_IDENTITY.
DEFAULT_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')"
SIGNING_IDENTITY="${MACSHOT_SIGN_IDENTITY:-$DEFAULT_IDENTITY}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "no Apple Development signing identity found in keychain." >&2
  echo "open Xcode → Settings → Accounts and add your Apple ID, or set MACSHOT_SIGN_IDENTITY." >&2
  exit 1
fi

DO_PULL=1
RESET_TCC=0
for arg in "$@"; do
  case "$arg" in
    --no-pull) DO_PULL=0 ;;
    --reset-tcc) RESET_TCC=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "==> macshot local prod build"
echo "    project:  $PROJECT_DIR"
echo "    identity: $SIGNING_IDENTITY"

cd "$PROJECT_DIR"

if [[ "$DO_PULL" == "1" ]]; then
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  echo "==> updating main from origin (current branch: $CURRENT_BRANCH)"
  git fetch origin
  git checkout main
  git pull --ff-only origin main
  RESTORE_BRANCH="$CURRENT_BRANCH"
else
  RESTORE_BRANCH=""
fi

echo "==> quitting any running instance"
osascript -e 'quit app "macshot"' 2>/dev/null || true
pkill -x macshot 2>/dev/null || true
sleep 1

echo "==> cleaning derived data"
rm -rf "$BUILD_DIR"

echo "==> xcodebuild Release"
xcodebuild \
  -project "$PROJECT" \
  -scheme macshot \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build | tail -5

if [[ ! -d "$APP_OUT" ]]; then
  echo "build failed: $APP_OUT not found" >&2
  exit 1
fi

echo "==> stripping Sparkle auto-update from Info.plist"
PLIST="$APP_OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :SUScheduledCheckInterval 0" "$PLIST" 2>/dev/null || true

echo "==> re-signing (Info.plist was modified) — preserving entitlements"
if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
  echo "missing entitlements file: $ENTITLEMENTS_FILE" >&2
  exit 1
fi

# Re-sign nested frameworks first, then the app with entitlements applied to
# the main bundle. --deep alone won't reapply entitlements correctly after
# Info.plist mutation.
find "$APP_OUT/Contents/Frameworks" -maxdepth 2 -name "*.framework" -type d 2>/dev/null \
  | while read -r fw; do
      codesign --force --sign "$SIGNING_IDENTITY" \
        --options runtime --timestamp=none "$fw" 2>/dev/null || true
    done

codesign --force --sign "$SIGNING_IDENTITY" \
  --entitlements "$ENTITLEMENTS_FILE" \
  --options runtime \
  --timestamp=none \
  "$APP_OUT"

codesign --verify --deep --strict --verbose=2 "$APP_OUT" 2>&1 | tail -3
echo "    entitlements check:"
codesign -d --entitlements - "$APP_OUT" 2>&1 \
  | grep -E "app-sandbox|network|camera|audio|files\." | head -10 | sed 's/^/      /'

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"

if [[ "$RESET_TCC" == "1" ]]; then
  echo "==> resetting TCC grants for $BUNDLE_ID (will need to re-grant once)"
  tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset SystemPolicyAllFiles "$BUNDLE_ID" 2>/dev/null || true
fi

echo "==> installing to $INSTALL_PATH (version $VERSION, $BUNDLE_ID)"
rm -rf "$INSTALL_PATH"
cp -R "$APP_OUT" "$INSTALL_PATH"
xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

echo "==> launching"
open "$INSTALL_PATH"

if [[ -n "$RESTORE_BRANCH" && "$RESTORE_BRANCH" != "main" ]]; then
  echo "==> restoring branch: $RESTORE_BRANCH"
  git checkout "$RESTORE_BRANCH"
fi

echo
echo "Done. macshot $VERSION installed and running."
echo "If permissions prompt: grant Screen Recording (and Accessibility if asked)."
echo "Future rebuilds keep the same code signature, so grants persist."
