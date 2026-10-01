#!/usr/bin/env bash
#
# Runs the example app's smoke checklist on an iOS simulator and fails if any step
# fails or the run never finishes. The checklist runs inside the real WKWebView,
# so this covers what unit tests can't: the native map mounting into the page,
# the camera landing where asked, remote icons being drawn, snapshots, and the
# rest of what App.svelte reads back. Each step logs `[smoke] ✓/✗ ...` and the
# run ends with `[smoke] done: ...`; the app's console is captured with
# `simctl launch --console-pty`.
#
# Expects `npm ci` to have run in both the repo root and example-app/.
#
#   npm run test:smoke
#   SIMULATOR_UDID=<udid> npm run test:smoke   # pick the simulator
#   SMOKE_TIMEOUT=600 npm run test:smoke       # seconds to wait for the run (default 300)
#
# Some steps (remote icon, geocoding, search) need network access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT}/example-app"
BUNDLE_ID="$(node -p "require('${APP_DIR}/capacitor.config.json').appId")"
TIMEOUT="${SMOKE_TIMEOUT:-300}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/apple-maps-smoke.XXXXXX")"
LOG="${WORK}/console.log"
LAUNCH_PID=""
cleanup() {
  [ -n "${LAUNCH_PID}" ] && kill "${LAUNCH_PID}" 2>/dev/null || true
  [ -n "${UDID:-}" ] && xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

step() { printf '\n==> %s\n' "$*"; }

# --- Simulator (same selection as test-ios.sh) ----------------------------------
UDID="${SIMULATOR_UDID:-}"
if [ -z "${UDID}" ]; then
  UDID=$(xcrun simctl list devices available \
    | grep -iE 'iPhone' \
    | grep -oiE '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}' \
    | head -n 1 || true)
fi
if [ -z "${UDID}" ]; then
  echo "No available iPhone simulator found. Install one via Xcode > Settings > Components." >&2
  exit 1
fi

# --- Build ------------------------------------------------------------------------
step "Building the plugin and the example app's web bundle"
(cd "${ROOT}" && npm run build >/dev/null)
(cd "${APP_DIR}" && npm run build >/dev/null && npx --no-install cap sync ios >/dev/null)

step "Building the iOS app for simulator ${UDID}"
xcodebuild build \
  -project "${APP_DIR}/ios/App/App.xcodeproj" \
  -scheme App \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "${WORK}/DerivedData" \
  CODE_SIGNING_ALLOWED=NO -quiet
APP_PATH="${WORK}/DerivedData/Build/Products/Debug-iphonesimulator/App.app"

# --- Run --------------------------------------------------------------------------
step "Booting the simulator and installing"
xcrun simctl boot "${UDID}" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "${UDID}" -b >/dev/null
xcrun simctl install "${UDID}" "${APP_PATH}"

step "Running the smoke checklist (timeout ${TIMEOUT}s)"
xcrun simctl launch --console-pty --terminate-running-process "${UDID}" "${BUNDLE_ID}" >"${LOG}" 2>&1 &
LAUNCH_PID=$!

finished=""
for _ in $(seq "${TIMEOUT}"); do
  if grep -q '\[smoke\] done:' "${LOG}"; then
    finished=1
    break
  fi
  if ! kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    break   # the app exited (crashed) before finishing
  fi
  sleep 1
done

grep '\[smoke\]' "${LOG}" | sed 's/.*\[smoke\] /  /' || true

if [ -z "${finished}" ]; then
  echo >&2
  echo "FAIL: the smoke run did not finish (crash, hang, or timeout after ${TIMEOUT}s). Last console output:" >&2
  tail -n 40 "${LOG}" >&2
  exit 1
fi
if grep -q '\[smoke\] ✗' "${LOG}"; then
  echo >&2
  echo "FAIL: $(grep -c '\[smoke\] ✗' "${LOG}") smoke step(s) failed" >&2
  exit 1
fi
if grep -q '\[smoke\] done: 0 passed' "${LOG}"; then
  echo "FAIL: no smoke steps ran" >&2
  exit 1
fi

step "Smoke checklist passed"
