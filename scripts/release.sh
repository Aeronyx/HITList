#!/bin/zsh
# HITList release: bump the build number (and optionally the version), regenerate, run the preflight
# tests, archive + export iOS and macOS, verify entitlements, upload to App Store Connect, commit and tag.
#
# Usage:
#   scripts/release.sh                 # full run, both platforms; preflight = core + macOS + iOS tests
#   scripts/release.sh --version 0.2.0 # also set MARKETING_VERSION; needs a "## 0.2.0" section in CHANGELOG.md
#   scripts/release.sh ios|macos       # one platform
#   scripts/release.sh --quick         # preflight runs core + macOS tests only (skips the ~10 min iOS suite)
#   scripts/release.sh --no-upload     # build and verify only
#   scripts/release.sh --no-bump       # keep the current build number
#   scripts/release.sh --skip-tests    # no preflight at all (emergencies only)
#   scripts/release.sh --skip-schema-check
#
# Tags: every upload is tagged build-N; a run with --version also tags vX.Y.Z. CHANGELOG.md's section for
# the version gets the build number and date appended to its heading.
#
# Environment overrides: ASC_KEY_ID, ASC_ISSUER_ID (App Store Connect API key, .p8 must live in
# ~/.appstoreconnect/private_keys/). Defaults are George's "hitlist-upload" key.
#
# Schema drift check: if a CloudKit management token is saved (`xcrun cktool save-token`), the script
# exports the Development and Production schemas and refuses to upload while they differ, because
# a build whose models need undeployed schema changes would fail to sync in Production. Without a
# token it prints a warning and continues. The Production export is also handed to the preflight
# (`CloudKitSchemaTests`, through TEST_RUNNER_HITLIST_CLOUDKIT_SCHEMA), which fails when Production lacks a
# field the models have: the diff alone is blind to a field missing from both environments, which is how
# three TaskItem fields went undeployed for a week and stopped a tester's sync (2026-11-06).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM_ID=UC8N98H3RT
CONTAINER_ID=iCloud.com.trammells.hitlist
SHARED_CONTAINER_ID=iCloud.com.trammells.hitlist.shared
KEY_ID="${ASC_KEY_ID:-RWK3KKN75R}"
ISSUER_ID="${ASC_ISSUER_ID:-1858583d-d6ee-4039-968e-e9c2c66e3ddd}"

PLATFORMS=(ios macos)
UPLOAD=1; BUMP=1; TESTS=1; QUICK=0; SCHEMA_CHECK=1; NEW_VERSION=""
expect_version=0
for arg in "$@"; do
  if (( expect_version )); then NEW_VERSION="$arg"; expect_version=0; continue; fi
  case "$arg" in
    ios) PLATFORMS=(ios) ;;
    macos) PLATFORMS=(macos) ;;
    --version) expect_version=1 ;;
    --version=*) NEW_VERSION="${arg#--version=}" ;;
    --quick) QUICK=1 ;;
    --no-upload) UPLOAD=0 ;;
    --no-bump) BUMP=0 ;;
    --skip-tests) TESTS=0 ;;
    --skip-schema-check) SCHEMA_CHECK=0 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg"; exit 2 ;;
  esac
done
(( expect_version )) && { echo "--version needs a value, e.g. --version 0.2.0"; exit 2; }
if [[ -n "$NEW_VERSION" ]]; then
  [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 0.2.0, got: $NEW_VERSION"; exit 2; }
  grep -qE "^## $NEW_VERSION( |\$)" CHANGELOG.md || { echo "CHANGELOG.md has no '## $NEW_VERSION' section; write what changed first"; exit 2; }
fi

step() { print -P "\n%F{cyan}== $1%f"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is dirty; commit or stash first so the release tag matches what was built"
fi

# ---- schema drift (first: nothing is bumped or built until the schemas match) ---------------------
# The models' fields reach CloudKit Development as soon as a Development build saves a record with them;
# Production only gets them when George deploys in the CloudKit dashboard. A build whose models need
# undeployed fields would fail to sync in Production, so this refuses to go on while the two differ.
if (( SCHEMA_CHECK && UPLOAD )); then
  step "CloudKit schema drift check"
  TMP=$(mktemp -d)
  # Every container the app syncs with: the task store's, and Shared Tasks' own (brief 51, 0.7.0).
  for CID in "$CONTAINER_ID" "$SHARED_CONTAINER_ID"; do
    if xcrun cktool export-schema --team-id "$TEAM_ID" --container-id "$CID" \
         --environment development --output-file "$TMP/$CID-dev.ckdb" >/dev/null 2>&1 &&
       xcrun cktool export-schema --team-id "$TEAM_ID" --container-id "$CID" \
         --environment production --output-file "$TMP/$CID-prod.ckdb" >/dev/null 2>&1; then
      if ! diff -q "$TMP/$CID-dev.ckdb" "$TMP/$CID-prod.ckdb" >/dev/null; then
        diff "$TMP/$CID-dev.ckdb" "$TMP/$CID-prod.ckdb" || true
        print -P "%F{yellow}Deploy first: icloud.developer.apple.com → CloudKit Database → $CID → Development → Deploy Schema Changes… → Production. Then run this again (nothing was changed here).%f"
        fail "$CID: Development schema differs from Production (see the lines above: '<' is Development, '>' Production). Or pass --skip-schema-check."
      fi
      echo "$CID: Development and Production schemas match."
      if [[ "$CID" == "$CONTAINER_ID" ]]; then
        # xcodebuild forwards TEST_RUNNER_* to the test process: the preflight's CloudKitSchemaTests reads the
        # export and fails if a field the models have is missing from Production (see the header).
        export TEST_RUNNER_HITLIST_CLOUDKIT_SCHEMA="$TMP/$CID-prod.ckdb"
      fi
    else
      print -P "%F{yellow}$CID: could not export its schemas (no cktool management token saved?); skipping its drift check. Run: xcrun cktool save-token --type management%f"
    fi
  done
fi

# ---- build number -------------------------------------------------------------------------------
CURRENT=$(grep -E '^[[:space:]]+CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
MARKETING=$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"')
[[ "$CURRENT" =~ ^[0-9]+$ ]] || fail "could not read CURRENT_PROJECT_VERSION from project.yml"
LOGDIR="$ROOT/build.noindex/logs"; mkdir -p "$LOGDIR"
if [[ -n "$NEW_VERSION" && "$NEW_VERSION" != "$MARKETING" ]]; then
  step "Version $MARKETING -> $NEW_VERSION"
  sed -i '' -E "s/^([[:space:]]+MARKETING_VERSION:) .*/\1 \"$NEW_VERSION\"/" project.yml
  sed -i '' -E "s/^([[:space:]]+CFBundleShortVersionString:) .*/\1 \"$NEW_VERSION\"/" project.yml
  grep -qE "^[[:space:]]+MARKETING_VERSION: \"$NEW_VERSION\"\$" project.yml || fail "MARKETING_VERSION change did not apply"
  grep -qE "^[[:space:]]+CFBundleShortVersionString: \"$NEW_VERSION\"\$" project.yml || fail "CFBundleShortVersionString change did not apply"
  MARKETING="$NEW_VERSION"
fi
if (( BUMP )); then
  NEXT=$((CURRENT + 1))
  step "Bump build $CURRENT -> $NEXT (version $MARKETING)"
  # BSD sed has no \s; use a POSIX class, then prove the bump landed (a silent no-op would re-upload the old build).
  sed -i '' -E "s/^([[:space:]]+CURRENT_PROJECT_VERSION:) .*/\1 $NEXT/" project.yml
  sed -i '' -E "s/^([[:space:]]+CFBundleVersion:) .*/\1 \"$NEXT\"/" project.yml
  grep -qE "^[[:space:]]+CURRENT_PROJECT_VERSION: $NEXT\$" project.yml || fail "CURRENT_PROJECT_VERSION bump did not apply"
  grep -qE "^[[:space:]]+CFBundleVersion: \"$NEXT\"\$" project.yml || fail "CFBundleVersion bump did not apply"
else
  NEXT=$CURRENT
  step "Keeping build $NEXT (version $MARKETING)"
fi

step "Generate Xcode project"
xcodegen generate >/dev/null

# ---- preflight ----------------------------------------------------------------------------------
# Nothing is archived until every suite passes: HITListCore, the app tests on the Mac and (unless --quick)
# on the iPhone simulator. The upload that follows cannot be taken back, so the bump is reverted on failure.
revert_bump() {
  git checkout -q -- project.yml
  xcodegen generate >/dev/null 2>&1 || true
}
if (( TESTS )); then
  SUITES=(core macos ios); (( QUICK )) && SUITES=(core macos)
  step "Preflight tests: ${SUITES[*]}"
  if ! scripts/test.sh "${SUITES[@]}"; then
    revert_bump
    fail "preflight tests failed; nothing was built or uploaded (build number reverted)"
  fi
else
  print -P "%F{yellow}Preflight tests skipped (--skip-tests).%f"
fi

# ---- archive / export / verify ------------------------------------------------------------------
# .noindex: Spotlight must not offer these app copies when George types "HITList".
ARCHIVES="$ROOT/build.noindex/archives"
mkdir -p "$ARCHIVES"
for p in $PLATFORMS; do
  case $p in
    ios)   DEST='generic/platform=iOS';   OUT="$ROOT/build.noindex/ios";   ARTIFACT="$OUT/HITList.ipa" ;;
    macos) DEST='generic/platform=macOS'; OUT="$ROOT/build.noindex/mac";   ARTIFACT="$OUT/HITList.pkg" ;;
  esac
  ARCHIVE="$ARCHIVES/HITList-$p.xcarchive"
  rm -rf "$ARCHIVE" "$OUT"

  step "Archive $p"
  if ! xcodebuild archive -project HITList.xcodeproj -scheme HITList -destination "$DEST" \
       -archivePath "$ARCHIVE" -allowProvisioningUpdates > "$LOGDIR/archive-$p.log" 2>&1; then
    grep -E "error:|failed with exit code|The following build commands failed" -A2 "$LOGDIR/archive-$p.log" | head -30
    tail -12 "$LOGDIR/archive-$p.log"
    fail "archive $p failed (log: $LOGDIR/archive-$p.log)"
  fi
  [[ -d "$ARCHIVE" ]] || fail "archive $p missing"

  step "Export $p"
  if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist ExportOptions.plist \
       -exportPath "$OUT" -allowProvisioningUpdates > "$LOGDIR/export-$p.log" 2>&1; then
    grep -E "error:|EXPORT FAILED" -A2 "$LOGDIR/export-$p.log" | head -20
    fail "export $p failed (log: $LOGDIR/export-$p.log)"
  fi
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
      ios)   ARTIFACT="$ROOT/build.noindex/ios/HITList.ipa" ;;
      macos) ARTIFACT="$ROOT/build.noindex/mac/HITList.pkg" ;;
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
  if [[ -n "$NEW_VERSION" ]]; then
    # "## 0.2.0" becomes "## 0.2.0 — build 6, 2026-11-01" so the changelog says what shipped when.
    sed -i '' -E "s/^## $NEW_VERSION\$/## $NEW_VERSION — build $NEXT, $(date +%Y-%m-%d)/" CHANGELOG.md
    git add CHANGELOG.md
  fi
  # The bump regenerates the project and Info.plist; commit them with it so the tag is reproducible.
  git add project.yml HITList.xcodeproj HITList/Info.plist
  git commit -q -m "Release $MARKETING ($NEXT)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
  git tag -f "build-$NEXT"
  echo "tagged build-$NEXT"
  if [[ -n "$NEW_VERSION" ]]; then
    git tag -f "v$NEW_VERSION"
    echo "tagged v$NEW_VERSION"
  fi
fi

print -P "\n%F{green}Done. Version $MARKETING build $NEXT.%f"
