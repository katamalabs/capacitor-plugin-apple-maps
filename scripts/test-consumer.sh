#!/usr/bin/env bash
#
# Installs the packed plugin into a throwaway Capacitor app and builds it the way
# a consumer would: from the npm tarball (not a link or `file:..`), so it catches
# what the repo's own tests can't - files missing from the package, broken type
# exports, and a native project that doesn't resolve under SPM or CocoaPods.
#
#   npm run test:consumer                 # both package managers
#   npm run test:consumer -- SPM          # just one (SPM or CocoaPods)
#   KEEP_CONSUMER_APP=1 npm run test:consumer   # leave the app behind to inspect
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANAGERS=("$@")
[ ${#MANAGERS[@]} -eq 0 ] && MANAGERS=(SPM CocoaPods)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/apple-maps-consumer.XXXXXX")"
cleanup() {
  if [ -n "${KEEP_CONSUMER_APP:-}" ]; then
    echo "Consumer app kept at ${WORK}/app"
  else
    rm -rf "${WORK}"
  fi
}
trap cleanup EXIT

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Pack ---------------------------------------------------------------------
step "Building and packing the plugin"
(cd "${ROOT}" && npm run build >/dev/null && npm pack --silent --pack-destination "${WORK}" >/dev/null)
TARBALL="$(ls "${WORK}"/*.tgz)"

# Everything a consumer needs must be in the tarball; anything else shouldn't be.
CONTENTS="$(tar -tzf "${TARBALL}")"
for required in \
  package/package.json \
  package/dist/plugin.cjs.js \
  package/dist/esm/index.js \
  package/dist/esm/index.d.ts \
  package/Package.swift \
  package/CapacitorPluginAppleMaps.podspec \
  package/ios/Sources/CapacitorAppleMapsPlugin/CapacitorAppleMapsPlugin.swift; do
  grep -qx "${required}" <<<"${CONTENTS}" || fail "${required#package/} is missing from the package"
done
if grep -qE '^package/(node_modules|example-app|src|site)/' <<<"${CONTENTS}"; then
  fail "package contains development-only directories"
fi
echo "Packed $(basename "${TARBALL}") ($(wc -l <<<"${CONTENTS}" | tr -d ' ') files)"

# --- Consumer app ---------------------------------------------------------------
step "Creating a consumer app"
APP="${WORK}/app"
mkdir -p "${APP}/www" "${APP}/src"
cd "${APP}"

cat > package.json <<EOF
{
  "name": "apple-maps-consumer",
  "private": true,
  "dependencies": {
    "@capacitor/core": "^8.0.0",
    "@capacitor/ios": "^8.0.0",
    "capacitor-plugin-apple-maps": "file:${TARBALL}"
  },
  "devDependencies": {
    "@capacitor/cli": "^8.0.0",
    "typescript": "^5.0.0"
  }
}
EOF
cat > capacitor.config.json <<'EOF'
{ "appId": "com.example.applemapsconsumer", "appName": "Consumer", "webDir": "www" }
EOF
echo '<!doctype html><title>Consumer</title>' > www/index.html

# Uses the public API the way an app would; a type error here means the
# published declarations are broken or the API changed shape.
cat > src/main.ts <<'EOF'
import { AppleMap, checkPermissions, geocode } from 'capacitor-plugin-apple-maps';
import type { LatLngBounds, Marker, PermissionStatus } from 'capacitor-plugin-apple-maps';

export async function demo(element: HTMLElement): Promise<LatLngBounds> {
  const map = await AppleMap.create({ id: 'm', element, config: { center: { lat: 0, lng: 0 }, zoom: 3 } });
  const marker: Marker = { coordinate: { lat: 1, lng: 2 }, markerId: 'a' };
  const ids: string[] = await map.addMarkers([marker]);
  await map.fitBounds([{ lat: 0, lng: 179 }, { lat: 0, lng: -179 }], 24);
  const status: PermissionStatus = await checkPermissions();
  const place = await geocode({ address: 'x' });
  void ids, status, place.latitude;
  return map.getMapBounds();
}
EOF
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022", "DOM"],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": false
  },
  "include": ["src"]
}
EOF

npm install --silent --no-audit --no-fund

step "Type-checking against the published declarations"
npx --no-install tsc -p .

step "Importing the package in Node (no DOM)"
node -e 'require("capacitor-plugin-apple-maps")'

# --- Native builds ----------------------------------------------------------------
for manager in "${MANAGERS[@]}"; do
  step "iOS with ${manager}"
  rm -rf ios
  npx --no-install cap add ios --packagemanager "${manager}" >/dev/null

  # Capacitor must have discovered the plugin and registered its native class.
  grep -q 'CapacitorAppleMapsPlugin' ios/App/App/capacitor.config.json \
    || fail "${manager}: CapacitorAppleMapsPlugin missing from the generated packageClassList"

  case "${manager}" in
    SPM)
      grep -q 'capacitor-plugin-apple-maps' ios/App/CapApp-SPM/Package.swift \
        || fail "SPM: plugin not added to CapApp-SPM/Package.swift"
      BUILD_TARGET=(-project ios/App/App.xcodeproj)
      ;;
    CocoaPods)
      grep -q "pod 'CapacitorPluginAppleMaps'" ios/App/Podfile \
        || fail "CocoaPods: plugin not added to the Podfile"
      BUILD_TARGET=(-workspace ios/App/App.xcworkspace)
      ;;
    *)
      fail "unknown package manager ${manager} (use SPM or CocoaPods)"
      ;;
  esac

  xcodebuild build "${BUILD_TARGET[@]}" -scheme App \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${WORK}/DerivedData-${manager}" \
    CODE_SIGNING_ALLOWED=NO -quiet \
    || fail "${manager}: xcodebuild failed"
  echo "${manager}: built"
done

step "Consumer install test passed (${MANAGERS[*]})"
