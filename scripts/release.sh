#!/bin/zsh
# HITList release: bump build number, regenerate, test, archive + export iOS and macOS,
# verify entitlements, upload to App Store Connect, commit and tag.
#
# Usage:
#   scripts/release.sh                 # full run, both platforms
#   scripts/release.sh ios|macos       # one platform
#   scripts/release.sh --no-upload     # build and verify only
#   scripts/release.sh --no-bump       # keep the current build number
#   scripts/release.sh --skip-tests    # skip HITListCore tests
#   scripts/release.sh --skip-schema-check
#
# Environment overrides: ASC_KEY_ID, ASC_ISSUER_ID (App Store Connect API key, .p8 must live in
# ~/.appstoreconnect/private_keys/). Defaults are George's "hitlist-upload" key.
#
# Schema drift check: if a CloudKit management token is saved (`xcrun cktool save-token`), the script
# exports the Development and Production schemas and refuses to upload while they differ, because
# a build whose models need undeployed schema changes would fail to sync in Production. Without a
# token it prints a warning and continues.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM_ID=UC8N98H3RT
CONTAINER_ID=iCloud.com.trammells.hitlist
KEY_ID="${ASC_KEY_ID:-RWK3KKN75R}"
ISSUER_ID="${ASC_ISSUER_ID:-1858583d-d6ee-4039-968e-e9c2c66e3ddd}"

PLATFORMS=(ios macos)
UPLOAD=1; BUMP=1; TESTS=1; SCHEMA_CHECK=1
for arg in "$@"; do
  case "$arg" in
    ios) PLATFORMS=(ios) ;;
    macos) PLATFORMS=(macos) ;;
    --no-upload) UPLOAD=0 ;;
    --no-bump) BUMP=0 ;;
    --skip-tests) TESTS=0 ;;
    --skip-schema-check) SCHEMA_CHECK=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg"; exit 2 ;;
  esac
done

step() { print -P "\n%F{cyan}== $1%f"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is dirty; commit or stash first so the release tag matches what was built"
fi

# ---- build number -------------------------------------------------------------------------------
CURRENT=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
MARKETING=$(grep -E '^\s+MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"')
if (( BUMP )); then
  NEXT=$((CURRENT + 1))
  step "Bump build $CURRENT -> $NEXT (version $MARKETING)"
  sed -i '' -E "s/^(\s+CURRENT_PROJECT_VERSION:) .*/\1 $NEXT/" project.yml
  sed -i '' -E "s/^(\s+CFBundleVersion:) .*/\1 \"$NEXT\"/" project.yml
else
  NEXT=$CURRENT
  step "Keeping build $NEXT (version $MARKETING)"
fi

step "Generate Xcode project"
xcodegen generate >/dev/null

if (( TESTS )); then
  step "HITListCore tests"
  (cd HITListCore && swift test 2>&1 | tail -3)
fi

# ---- schema drift -------------------------------------------------------------------------------
if (( SCHEMA_CHECK && UPLOAD )); then
  step "CloudKit schema drift check"
  TMP=$(mktemp -d)
  if xcrun cktool export-schema --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
       --environment development --output-file "$TMP/dev.ckdb" >/dev/null 2>&1 &&
     xcrun cktool export-schema --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
       --environment production --output-file "$TMP/prod.ckdb" >/dev/null 2>&1; then
    if ! diff -q "$TMP/dev.ckdb" "$TMP/prod.ckdb" >/dev/null; then
      diff "$TMP/dev.ckdb" "$TMP/prod.ckdb" || true
      fail "Development schema differs from Production. Deploy it in the CloudKit dashboard first, or pass --skip-schema-check."
    fi
    echo "Development and Production schemas match."
  else
    print -P "%F{yellow}No cktool management token saved; skipping drift check. Run: xcrun cktool save-token --type management%f"
  fi
fi

# ---- archive / export / verify ------------------------------------------------------------------
ARCHIVES="$ROOT/build/archives"
mkdir -p "$ARCHIVES"
for p in $PLATFORMS; do
  case $p in
    ios)   DEST='generic/platform=iOS';   OUT="$ROOT/build/ios";   ARTIFACT="$OUT/HITList.ipa" ;;
    macos) DEST='generic/platform=macOS'; OUT="$ROOT/build/mac";   ARTIFACT="$OUT/HITList.pkg" ;;
  esac
  ARCHIVE="$ARCHIVES/HITList-$p.xcarchive"
  rm -rf "$ARCHIVE" "$OUT"

  step "Archive $p"
  xcodebuild archive -project HITList.xcodeproj -scheme HITList -destination "$DEST" \
    -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet 2>&1 | grep -E "error:|ARCHIVE FAILED" && fail "archive $p failed" || true
  [[ -d "$ARCHIVE" ]] || fail "archive $p missing"

  step "Export $p"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions.plist \
    -exportPath "$OUT" -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT FAILED" && fail "export $p failed" || true
  [[ -f "$ARTIFACT" ]] || fail "export $p produced no artifact"

  step "Verify entitlements $p"
  X=$(mktemp -d)
  if [[ $p == ios ]]; then
    unzip -q "$ARTIFACT" -d "$X"; APP="$X/Payload/HITList.app"
  else
    pkgutil --expand-full "$ARTIFACT" "$X/pkg"; APP="$X/pkg/com.trammells.hitlist.pkg/Payload/HITList.app"
  fi
  ENT=$(codesign -d --entitlements :- "$APP" 2>/dev/null)
  echo "$ENT" | grep -q "icloud-container-development-container-identifiers" && fail "development-only CloudKit key present; App Store Connect will reject it"
  echo "$ENT" | grep -q "<string>Production</string>" || fail "icloud-container-environment is not Production"
  echo "$ENT" | grep -q "aps-environment</key><string>production" || fail "push environment is not production"
  if [[ $p == macos ]]; then
    echo "$ENT" | grep -q "com.apple.security.app-sandbox</key><true" || fail "macOS build is not sandboxed"
  fi
  echo "ok: $(ls -la "$ARTIFACT" | awk '{print $5}') bytes"
done

# ---- upload -------------------------------------------------------------------------------------
if (( UPLOAD )); then
  for p in $PLATFORMS; do
    case $p in
      ios)   ARTIFACT="$ROOT/build/ios/HITList.ipa" ;;
      macos) ARTIFACT="$ROOT/build/mac/HITList.pkg" ;;
    esac
    step "Upload $p"
    LOG=$(mktemp)
    if xcrun altool --upload-app -f "$ARTIFACT" -t "$p" --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID" >"$LOG" 2>&1; then
      grep -E "Delivery UUID" "$LOG" || true
    else
      grep -E "ERROR|description" "$LOG" || cat "$LOG"
      fail "upload $p failed"
    fi
  done
fi

# ---- commit + tag -------------------------------------------------------------------------------
if (( BUMP )); then
  step "Commit and tag build $NEXT"
  git add project.yml
  git commit -q -m "Release $MARKETING ($NEXT)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
  git tag -f "build-$NEXT"
  echo "tagged build-$NEXT"
fi

print -P "\n%F{green}Done. Version $MARKETING build $NEXT.%f"
