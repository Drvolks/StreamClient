#!/bin/bash
# Archive and upload NextPVR + Dispatcharr for iOS, tvOS, and macOS to TestFlight
#
# Usage:
#   ./archive-all.sh                                   # everything
#   ./archive-all.sh --schemes Dispatcharr --platforms tvOS
#   ./archive-all.sh --platforms iOS,tvOS
#
#   --schemes    comma-separated: NextPVR, Dispatcharr   (default: both)
#   --platforms  comma-separated: iOS, tvOS, macOS       (default: all)
#
# Archives and exports run one at a time (each xcodebuild already uses every
# core, and exports talk to Apple for signing); uploads run in parallel.
#
# Requirements:
#   App Store Connect API key (.p8 file)
#   Apple Distribution certificate in local Keychain
#   Set these environment variables or edit the values below:
#     ASC_KEY_ID       - API Key ID
#     ASC_ISSUER_ID    - Issuer ID
#     ASC_KEY_PATH     - Path to AuthKey_XXXX.p8 file

set -e

# --- What to build (options) ---

ALL_SCHEMES=(NextPVR Dispatcharr)
ALL_PLATFORMS=(iOS tvOS macOS)
SCHEMES=("${ALL_SCHEMES[@]}")
PLATFORMS=("${ALL_PLATFORMS[@]}")

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Splits a comma-separated list and checks each value against the allowed ones.
parse_list() {
  local label="$1" value="$2"
  shift 2
  local allowed=("$@") item ok
  PARSED=()
  IFS=',' read -ra PARSED <<< "$value"
  if [ "${#PARSED[@]}" -eq 0 ]; then
    echo "ERROR: $label needs at least one value (${allowed[*]})." >&2
    exit 2
  fi
  for item in "${PARSED[@]}"; do
    ok=0
    for candidate in "${allowed[@]}"; do
      [ "$item" = "$candidate" ] && ok=1
    done
    if [ "$ok" -eq 0 ]; then
      echo "ERROR: unknown $label '$item' (expected: ${allowed[*]})." >&2
      exit 2
    fi
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --schemes)
      [ "$#" -ge 2 ] || { echo "ERROR: --schemes needs a value." >&2; exit 2; }
      parse_list "scheme" "$2" "${ALL_SCHEMES[@]}"
      SCHEMES=("${PARSED[@]}")
      shift 2 ;;
    --platforms)
      [ "$#" -ge 2 ] || { echo "ERROR: --platforms needs a value." >&2; exit 2; }
      parse_list "platform" "$2" "${ALL_PLATFORMS[@]}"
      PLATFORMS=("${PARSED[@]}")
      shift 2 ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      echo "ERROR: unknown option '$1'." >&2
      usage >&2
      exit 2 ;;
  esac
done

echo "=== Schemes: ${SCHEMES[*]} | Platforms: ${PLATFORMS[*]} ==="

# App Store Connect API key config
KEY_ID="${ASC_KEY_ID:?Set ASC_KEY_ID environment variable}"
ISSUER_ID="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID environment variable}"
KEY_PATH="${ASC_KEY_PATH:?Set ASC_KEY_PATH environment variable}"

ARCHIVE_DIR=~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)
EXPORT_DIR=/tmp/NexusPVR-export
PROJECT=NexusPVR.xcodeproj
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_PLIST="$SCRIPT_DIR/ExportOptions.plist"

AUTH_FLAGS=(-allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID")

EXPORT_RETRY_MAX_ATTEMPTS="${EXPORT_RETRY_MAX_ATTEMPTS:-4}"
EXPORT_RETRY_BASE_DELAY_SECONDS="${EXPORT_RETRY_BASE_DELAY_SECONDS:-15}"

rm -rf "$EXPORT_DIR"

# --- Determine build number from git commit count ---

cd "$SCRIPT_DIR"
BUILD_NUMBER=$(git rev-list HEAD --count)
echo "=== Build number (git commit count): $BUILD_NUMBER ==="

retry_export_archive() {
  local attempt=1
  local max_attempts="$1"
  shift

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "=== Export attempt $attempt/$max_attempts ==="
    if xcodebuild -exportArchive "$@"; then
      return 0
    fi

    if [ "$attempt" -eq "$max_attempts" ]; then
      echo "ERROR: Export failed after $max_attempts attempts."
      return 1
    fi

    local sleep_seconds=$((EXPORT_RETRY_BASE_DELAY_SECONDS * attempt))
    echo "Export failed (likely transient). Retrying in ${sleep_seconds}s..."
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

# --- Archive ---

for SCHEME in "${SCHEMES[@]}"; do
  for PLATFORM in "${PLATFORMS[@]}"; do
    echo "=== Archiving $SCHEME ($PLATFORM) ==="
    xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" \
      -destination "generic/platform=$PLATFORM" \
      -archivePath "$ARCHIVE_DIR/$SCHEME-$PLATFORM.xcarchive" \
      "${AUTH_FLAGS[@]}"
  done
done

# --- Stamp build number in archives ---

for SCHEME in "${SCHEMES[@]}"; do
  for PLATFORM in "${PLATFORMS[@]}"; do
    ARCHIVE="$ARCHIVE_DIR/$SCHEME-$PLATFORM.xcarchive"
    case "$PLATFORM" in
      macOS)
        # macOS PRODUCT_NAME differs from scheme name
        case "$SCHEME" in
          NextPVR)     MAC_APP="StreamClient for NextPVR" ;;
          Dispatcharr) MAC_APP="StreamClient" ;;
          *)           MAC_APP="$SCHEME" ;;
        esac
        APP_PLIST="$ARCHIVE/Products/Applications/$MAC_APP.app/Contents/Info.plist" ;;
      *)     APP_PLIST="$ARCHIVE/Products/Applications/$SCHEME.app/Info.plist" ;;
    esac
    ARCHIVE_PLIST="$ARCHIVE/Info.plist"
    echo "=== Stamping build $BUILD_NUMBER in $SCHEME ($PLATFORM) ==="
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PLIST"
    /usr/libexec/PlistBuddy -c "Set :ApplicationProperties:CFBundleVersion $BUILD_NUMBER" "$ARCHIVE_PLIST"
  done
done

# --- Export (sign for distribution) ---

for SCHEME in "${SCHEMES[@]}"; do
  for PLATFORM in "${PLATFORMS[@]}"; do
    echo "=== Exporting $SCHEME ($PLATFORM) ==="
    mkdir -p "$EXPORT_DIR/$SCHEME/$PLATFORM"
    retry_export_archive "$EXPORT_RETRY_MAX_ATTEMPTS" \
      -archivePath "$ARCHIVE_DIR/$SCHEME-$PLATFORM.xcarchive" \
      -exportOptionsPlist "$EXPORT_PLIST" \
      -exportPath "$EXPORT_DIR/$SCHEME/$PLATFORM" \
      "${AUTH_FLAGS[@]}"
  done
done

# --- Upload to TestFlight (in parallel) ---

UPLOAD_LOG_DIR="$EXPORT_DIR/upload-logs"
mkdir -p "$UPLOAD_LOG_DIR"
UPLOAD_PIDS=()
UPLOAD_NAMES=()
UPLOAD_LOGS=()

for SCHEME in "${SCHEMES[@]}"; do
  for PLATFORM in "${PLATFORMS[@]}"; do
    ARTIFACT=$(find "$EXPORT_DIR/$SCHEME/$PLATFORM" \( -name "*.ipa" -o -name "*.pkg" \) -print -quit)
    if [ -z "$ARTIFACT" ]; then
      echo "ERROR: No IPA/PKG found for $SCHEME ($PLATFORM) in $EXPORT_DIR/$SCHEME/$PLATFORM"
      exit 1
    fi

    case "$PLATFORM" in
      iOS)   TYPE=ios ;;
      tvOS)  TYPE=appletvos ;;
      macOS) TYPE=osx ;;
    esac

    echo "=== Uploading $SCHEME ($PLATFORM) to TestFlight ==="
    xcrun altool --upload-app \
      -f "$ARTIFACT" \
      -t "$TYPE" \
      --apiKey "$KEY_ID" \
      --apiIssuer "$ISSUER_ID" \
      > "$UPLOAD_LOG_DIR/$SCHEME-$PLATFORM.log" 2>&1 &
    UPLOAD_PIDS+=($!)
    UPLOAD_NAMES+=("$SCHEME ($PLATFORM)")
    UPLOAD_LOGS+=("$UPLOAD_LOG_DIR/$SCHEME-$PLATFORM.log")
  done
done

# Wait for every upload, then report: one failure must not hide the others.
UPLOAD_FAILED=0
for i in "${!UPLOAD_PIDS[@]}"; do
  NAME="${UPLOAD_NAMES[$i]}"
  if wait "${UPLOAD_PIDS[$i]}"; then
    echo "=== Uploaded $NAME ==="
  else
    echo "ERROR: Upload failed for $NAME:"
    UPLOAD_FAILED=1
  fi
  sed 's/^/    /' "${UPLOAD_LOGS[$i]}"
done

if [ "$UPLOAD_FAILED" -ne 0 ]; then
  echo "ERROR: At least one upload failed; not tagging."
  exit 1
fi

# --- Tag git commit with build number ---

TAG="build-$BUILD_NUMBER"
echo "=== Tagging commit as $TAG ==="
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  EXISTING_TAG_COMMIT=$(git rev-list -n 1 "$TAG")
  CURRENT_COMMIT=$(git rev-parse HEAD)
  if [ "$EXISTING_TAG_COMMIT" = "$CURRENT_COMMIT" ]; then
    echo "Tag $TAG already exists on current commit; skipping tag creation."
  else
    echo "ERROR: Tag $TAG already exists on a different commit ($EXISTING_TAG_COMMIT)."
    echo "Refusing to retag. Create a new commit or choose another tag."
    exit 1
  fi
else
  git tag "$TAG"
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists on origin; skipping push."
else
  git push origin "$TAG"
fi

echo "=== Archived and uploaded to TestFlight: ${SCHEMES[*]} / ${PLATFORMS[*]} ==="
