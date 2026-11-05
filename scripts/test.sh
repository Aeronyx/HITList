#!/bin/zsh
# HITList tests: HITListCore `swift test`, then the app test bundle on macOS and the iPhone simulator.
# Prints one summary line per suite and exits non-zero if any suite fails. Runs from any directory.
#
# Usage:
#   scripts/test.sh                    # core, macos, ios
#   scripts/test.sh core macos         # any subset, in the order given
#   scripts/test.sh ui                 # the iPhone UI tests (XCUITest, scheme HITListUITests); never by default
#   scripts/test.sh --unsigned macos   # build without signing, the way CI does
#
# Environment overrides: DEVELOPER_DIR, SIMULATOR (default "iPhone 17").
# Full logs go to a temporary directory; its path is printed when a suite fails.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIMULATOR="${SIMULATOR:-iPhone 17}"

signing=(-allowProvisioningUpdates)
suites=()
for arg in "$@"; do
  case "$arg" in
    # xcodebuild forwards TEST_RUNNER_* from its own environment (not from build settings) to the test
    # process as HITLIST_UNSIGNED=1; tests that need an entitlement skip on it.
    --unsigned) signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO); export TEST_RUNNER_HITLIST_UNSIGNED=1 ;;
    core|macos|ios|ui) suites+=("$arg") ;;
    *) print -u2 "unknown argument: $arg (expected core, macos, ios, ui, --unsigned)"; exit 2 ;;
  esac
done
(( ${#suites} )) || suites=(core macos ios)

# HITLIST_TEST_LOGS pins the log directory (CI uploads it as an artifact); otherwise a temp dir.
if [[ -n "${HITLIST_TEST_LOGS:-}" ]]; then LOGS="$HITLIST_TEST_LOGS"; mkdir -p "$LOGS"
else LOGS="$(mktemp -d "${${TMPDIR:-/tmp}%/}/hitlist-tests.XXXXXX")"; fi
failed=0
summary=()

# The last "Executed N tests, with [S tests skipped and] F failures" line is the run total (XCTest prints
# one per test class too, and adds the skipped clause only when something was skipped).
xctest_total() {
  grep -E 'Executed [0-9]+ tests?, with ([0-9]+ tests? skipped and )?[0-9]+ failures?' "$1" | tail -1 \
    | sed -E 's/^[[:space:]]*Executed ([0-9]+) tests?, with (([0-9]+) tests? skipped and )?([0-9]+) failures?.*/\1 tests, \4 failures, \3 skipped/; s/, +skipped$//'
}

run_suite() {
  local name="$1"; shift
  local log="$LOGS/$name.log" start=$SECONDS
  print "▸ $name"
  "$@" > "$log" 2>&1
  local code=$? counts
  counts="$(xctest_total "$log")"
  [[ -n "$counts" ]] || counts="no tests ran (build failed?)"
  if (( code == 0 )); then
    summary+=("✔ $name: $counts in $(( SECONDS - start ))s")
  else
    summary+=("✘ $name: $counts, exit $code (log: $log)")
    failed=1
    # Surface the cause right away; the full log stays on disk.
    print -- "--- $name: errors ---"
    grep -E "(^|: )(error|fatal error): |xcodebuild: error|Testing failed|\*\* (BUILD|TEST) FAILED" "$log" | sort -u | head -40
    print -- "--- $name: last 15 lines ---"
    tail -15 "$log"
  fi
}

for suite in "${suites[@]}"; do
  case "$suite" in
    core)  run_suite core swift test --package-path HITListCore ;;
    macos) run_suite macos xcodebuild test -project HITList.xcodeproj -scheme HITList \
             -destination 'platform=macOS' "${signing[@]}" ;;
    ios)   run_suite ios xcodebuild test -project HITList.xcodeproj -scheme HITList \
             -destination "platform=iOS Simulator,name=$SIMULATOR" "${signing[@]}" ;;
    ui)    run_suite ui xcodebuild test -project HITList.xcodeproj -scheme HITListUITests \
             -destination "platform=iOS Simulator,name=$SIMULATOR" "${signing[@]}" ;;
  esac
done

print
print -l -- "${summary[@]}"
# Keep logs when a caller pinned the directory (CI uploads them); otherwise clean up on success.
(( failed )) || [[ -n "${HITLIST_TEST_LOGS:-}" ]] || rm -rf "$LOGS"
exit $failed
