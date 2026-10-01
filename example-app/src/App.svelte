<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { Capacitor } from '@capacitor/core';
  import {
    AppleMap,
    checkPermissions,
    geocode,
    requestPermissions,
    reverseGeocode,
    searchAutocomplete,
    searchPlaces,
    searchResolve,
  } from 'capacitor-plugin-apple-maps';
  import { GoogleMap, LatLngBounds, MapType } from '@capacitor/google-maps';

  // ── Provider pick ─────────────────────────────────────────────────────────
  // Both plugins expose the same create/addMarkers/listeners API, so the app
  // picks a provider once. Apple Maps needs no key; Google Maps needs one on
  // Android (AndroidManifest) and web (below). Each branch then exercises the
  // *same* feature set — overlays, draggable pins, a control bar, listeners and
  // a smoke checklist — so the two providers stay at parity. A few methods have
  // no native Google equivalent (runtime color scheme, long-press, snapshot,
  // updateMarkers); those are the only places the Google branch does less, and
  // each is called out in a comment where it would otherwise appear.
  //
  // Apple also goes *beyond* Google parity, and the iOS smoke run touches each:
  // permissions (check/request), camera bearing + tilt, getMapType, marker
  // opacity/tint/z-index, dashed + geodesic polylines, programmatic
  // select/deselect, camera boundary, 3D buildings, user tracking + the native
  // tracking button, and overlay-tap + my-location-tap listeners.
  const isIOS = Capacitor.getPlatform() === 'ios';
  const googleKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY ?? '';

  // On Android/web a missing key would crash Google Maps natively (nothing JS
  // can catch), so show a hint instead of creating the map.
  const needsKey = !isIOS && !googleKey;
  const provider = isIOS ? 'Apple Maps (MapKit)' : 'Google Maps';

  const center = { lat: 37.7749, lng: -122.4194 }; // San Francisco

  // A solid magenta 32×32 PNG served over https, for the remote-icon step: the
  // color is easy to find in snapshot pixels. Any https image of one solid,
  // unusual color would do.
  const REMOTE_ICON_URL = 'https://placehold.co/32x32/ff00ff/ff00ff.png';
  const markers = [
    { markerId: 'sf', coordinate: center, title: 'San Francisco', snippet: 'City Hall area' },
    { markerId: 'ggb', coordinate: { lat: 37.8199, lng: -122.4783 }, title: 'Golden Gate Bridge', snippet: '1937' },
    {
      markerId: 'wharf',
      coordinate: { lat: 37.8087, lng: -122.4098 },
      title: "Fisherman's Wharf",
      snippet: 'Pier 39 · drag me',
      // Press-and-hold, then drag, to move this pin (both providers). Zoom in
      // first if it's clustered with the others. Both plugins accept `draggable`.
      draggable: true,
    },
    {
      // A standalone pin, placed well south of the SF trio so it never clusters
      // (a lone pin always renders individually) — tap it and its info window
      // (native callout) pops up. On iOS this needs `showInfoWindows: true`;
      // Google shows the title/snippet callout on tap with no extra config.
      markerId: 'info-demo',
      coordinate: { lat: 37.6213, lng: -122.379 },
      title: 'Tap me',
      snippet: 'This is an info window',
    },
  ];

  let element = $state<HTMLElement>();
  // Shared handle used by the platform-agnostic paths (create/destroy/markers).
  let map: AppleMap | GoogleMap | undefined;
  // Per-provider handles, assigned only on their platform, so provider-only
  // calls type-check without casting the shared union everywhere.
  let appleMap: AppleMap | undefined;
  let googleMap: GoogleMap | undefined;
  let note = $state('');

  // Results of the smoke sequence, rendered as a ✓/✗ checklist.
  let steps = $state<{ name: string; ok: boolean; detail: string }[]>([]);
  // Apple returns one flat id list and removes them all with removeOverlays.
  let overlayIds = $state<string[]>([]);
  // Google removes overlays per type, so track the three id lists separately.
  let googleOverlays = $state<{ polylines: string[]; polygons: string[]; circles: string[] }>({
    polylines: [],
    polygons: [],
    circles: [],
  });
  const googleOverlayCount = $derived(
    googleOverlays.polylines.length + googleOverlays.polygons.length + googleOverlays.circles.length,
  );
  // Tracks the current base map type; the toggle label reflects the *next* action.
  let satellite = $state(false);
  // Appearance-toggle state, so each button's label reflects the *next* action.
  let traffic = $state(false);
  let dark = $state(false);

  // Android draws the Google map BEHIND the webview and shows it through a
  // transparent element, so every layer above the map must be see-through or you
  // just see the page background. iOS/web render the map into the element itself.
  const isAndroid = Capacitor.getPlatform() === 'android';

  const errMsg = (err: unknown) => (err instanceof Error ? err.message : String(err));

  // A bounds box around the 3 markers: southwest = min lat/lng, northeast =
  // max lat/lng, center = the average. Used by fitBounds when no live bounds
  // are handy. Shape matches both providers' LatLngBounds fields.
  function markerBounds() {
    const lats = markers.map((m) => m.coordinate.lat);
    const lngs = markers.map((m) => m.coordinate.lng);
    const south = Math.min(...lats);
    const north = Math.max(...lats);
    const west = Math.min(...lngs);
    const east = Math.max(...lngs);
    return {
      southwest: { lat: south, lng: west },
      northeast: { lat: north, lng: east },
      center: { lat: (south + north) / 2, lng: (west + east) / 2 },
    };
  }

  // Run one named smoke step, recording ✓ + detail or ✗ + error into `steps`.
  async function step(name: string, run: () => Promise<string>) {
    try {
      const detail = await run();
      steps = [...steps, { name, ok: true, detail }];
      // Mirrored to the console (Xcode / `simctl launch --console`) so a run can
      // be read without scrolling the on-screen panel.
      console.log(`[smoke] ✓ ${name}: ${detail}`);
    } catch (err) {
      steps = [...steps, { name, ok: false, detail: errMsg(err) }];
      console.log(`[smoke] ✗ ${name}: ${errMsg(err)}`);
    }
  }

  // ── Step assertions ───────────────────────────────────────────────────────
  // A step should fail when the result is wrong, not only when the call throws:
  // each check reads something back (camera, bounds, map type, rendered pixels)
  // and throws with what it saw.
  function check(condition: boolean, message: string): asserts condition {
    if (!condition) throw new Error(message);
  }

  const near = (a: number, b: number, tolerance: number) => Math.abs(a - b) <= tolerance;

  function checkIds(ids: string[], count: number) {
    check(
      ids.length === count && ids.every((id) => id.length > 0) && new Set(ids).size === ids.length,
      `expected ${count} unique id${count === 1 ? '' : 's'}, got ${JSON.stringify(ids)}`,
    );
  }

  // The call must reject with this plugin error code.
  async function checkRejects(run: () => Promise<unknown>, code: string) {
    try {
      await run();
    } catch (err) {
      const actual = (err as { code?: string }).code;
      check(actual === code, `expected ${code}, got ${actual ?? errMsg(err)}`);
      return;
    }
    throw new Error(`expected ${code}, but the call resolved`);
  }

  type Bounds = { southwest: LatLng; northeast: LatLng };
  type LatLng = { lat: number; lng: number };

  // Whether `p` lies inside `b`, allowing `slack` degrees and a box that crosses
  // the antimeridian (southwest.lng > northeast.lng).
  function contains(b: Bounds, p: LatLng, slack = 0) {
    const { southwest: sw, northeast: ne } = b;
    const latOk = p.lat >= sw.lat - slack && p.lat <= ne.lat + slack;
    const lngOk =
      sw.lng <= ne.lng
        ? p.lng >= sw.lng - slack && p.lng <= ne.lng + slack
        : p.lng >= sw.lng - slack || p.lng <= ne.lng + slack;
    return latOk && lngOk;
  }

  // Decode a snapshot data URL into a pixel reader (x/y in image pixels).
  async function readSnapshot(dataUrl: string) {
    const image = new Image();
    image.src = dataUrl;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    check(ctx !== null, 'no 2d canvas context');
    ctx.drawImage(image, 0, 0);
    return {
      width: canvas.width,
      height: canvas.height,
      // True if any pixel within `radius` of (x, y) passes `test`.
      anyNear(x: number, y: number, radius: number, test: (r: number, g: number, b: number) => boolean) {
        const left = Math.max(0, Math.round(x - radius));
        const top = Math.max(0, Math.round(y - radius));
        const size = radius * 2 + 1;
        const { data } = ctx.getImageData(left, top, size, size);
        for (let i = 0; i < data.length; i += 4) {
          if (test(data[i], data[i + 1], data[i + 2])) return true;
        }
        return false;
      },
    };
  }

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  // ── iOS smoke sequence ──────────────────────────────────────────────────
  // Touch each AppleMap method and check the outcome where it can be read back,
  // keeping any overlay ids for later cleanup. Steps that only prove a call
  // resolved (no read-back exists) say so in their detail text.
  async function runAppleSmokeSequence(am: AppleMap, markerIds: string[]) {
    await step('addMarkers ids', async () => {
      // Caller-supplied markerIds are echoed back verbatim, in order.
      const expected = markers.map((m) => m.markerId);
      check(
        JSON.stringify(markerIds) === JSON.stringify(expected),
        `expected ${expected.join(',')}, got ${markerIds.join(',')}`,
      );
      return `${markerIds.length} ids`;
    });

    await step('getCameraPosition', async () => {
      const pos = await am.getCameraPosition();
      check(
        near(pos.latitude, center.lat, 0.001) && near(pos.longitude, center.lng, 0.001),
        `camera at ${pos.latitude.toFixed(4)},${pos.longitude.toFixed(4)}, expected the create center`,
      );
      check(near(pos.zoom, 11, 0.5), `zoom ${pos.zoom.toFixed(2)}, expected ~11`);
      check(contains(pos.bounds, center), 'reported bounds do not contain the center');
      return `zoom ${pos.zoom.toFixed(1)}, bearing ${pos.bearing.toFixed(0)}°, tilt ${pos.angle.toFixed(0)}°`;
    });

    await step('setMapType + getMapType', async () => {
      check((await am.getMapType()) === 'standard', 'initial map type is not standard');
      await am.setMapType('hybrid');
      const switched = await am.getMapType();
      await am.setMapType('standard');
      check(switched === 'hybrid', `read back ${switched} after setting hybrid`);
      check((await am.getMapType()) === 'standard', 'did not switch back to standard');
      return 'standard → hybrid → standard';
    });

    await step('checkPermissions', async () => {
      // Read-only — never prompts. requestPermissions() is wired to "My location".
      const status = await checkPermissions();
      check(['prompt', 'granted', 'denied'].includes(status.location), `unexpected state ${status.location}`);
      return `location: ${status.location}`;
    });

    await step('addPolylines', async () => {
      const ids = await am.addPolylines([
        { path: markers.map((m) => m.coordinate), strokeColor: '#2563eb', strokeWeight: 4, strokeOpacity: 0.9 },
      ]);
      checkIds(ids, 1);
      overlayIds = [...overlayIds, ...ids];
      return '1 id';
    });

    await step('addPolygons', async () => {
      const ids = await am.addPolygons([
        {
          paths: markers.map((m) => m.coordinate),
          strokeColor: '#2563eb',
          strokeWeight: 2,
          fillColor: '#3b82f6',
          fillOpacity: 0.2,
        },
      ]);
      checkIds(ids, 1);
      overlayIds = [...overlayIds, ...ids];
      return '1 id';
    });

    await step('addCircles', async () => {
      const ids = await am.addCircles([
        { center, radius: 1500, strokeColor: '#2563eb', fillColor: '#3b82f6', fillOpacity: 0.2 },
      ]);
      checkIds(ids, 1);
      overlayIds = [...overlayIds, ...ids];
      return '1 id';
    });

    await step('fitBounds', async () => {
      // Exercise the coordinate-array overload: pass the raw pins and let the
      // wrapper compute the bounding box. Not animated, so the read-back below
      // sees the final framing.
      await am.fitBounds(
        markers.map((m) => m.coordinate),
        48,
        false,
      );
      const bounds = await am.getMapBounds();
      const outside = markers.filter((m) => !contains(bounds, m.coordinate));
      check(outside.length === 0, `not in view: ${outside.map((m) => m.markerId).join(', ')}`);
      return 'every pin in view';
    });

    await step('addMarker + removeMarker', async () => {
      const id = await am.addMarker({
        coordinate: { lat: center.lat - 0.02, lng: center.lng - 0.02 },
        title: 'Temp pin',
      });
      checkIds([id], 1);
      // selectMarker resolves only for a marker the map knows about.
      await am.selectMarker(id);
      await am.deselectMarker();
      await am.removeMarker(id);
      await checkRejects(() => am.selectMarker(id), 'MARKER_NOT_FOUND');
      return `id ${id.slice(0, 8)}… added, then gone`;
    });

    await step('selectMarker rejects unknown id', async () => {
      await checkRejects(() => am.selectMarker('no-such-marker'), 'MARKER_NOT_FOUND');
      return 'MARKER_NOT_FOUND';
    });

    await step('updateMarkers', async () => {
      await am.updateMarkers([
        { markerId: 'sf', coordinate: { lat: center.lat + 0.01, lng: center.lng }, title: 'San Francisco (moved)' },
      ]);
      await am.selectMarker('sf');
      await am.deselectMarker();
      return 'resolved (position not readable)';
    });

    await step('appearance toggles', async () => {
      // Touch each appearance setter once, then restore the visible defaults so
      // the map looks normal after the smoke run (compass on, POI on, standard
      // color scheme). Scale is left on so the config vs runtime paths differ.
      // None of these has a getter, so this only proves the calls resolve.
      await am.setTrafficEnabled(true);
      await am.setPointsOfInterestEnabled(false);
      await am.setCompassEnabled(false);
      await am.setScaleEnabled(true);
      await am.setColorScheme('dark');
      await am.setColorScheme('default');
      await am.setCompassEnabled(true);
      await am.setPointsOfInterestEnabled(true);
      await am.setTrafficEnabled(false);
      return 'resolved (no getters)';
    });

    await step('draggable toggle', async () => {
      // The 'wharf' pin is draggable from create; toggle it off and back on via
      // updateMarkers to exercise that path. Actual dragging needs a real touch,
      // so the on-device tester drags the pin and watches the `note` line.
      await am.updateMarkers([{ markerId: 'wharf', draggable: false }]);
      await am.updateMarkers([{ markerId: 'wharf', draggable: true }]);
      return 'resolved; drag the wharf pin by hand';
    });

    await step('gestures + padding', async () => {
      // Disable rotate/pitch, keep pan+zoom, and inset the map so the controls
      // clear the header; then restore full gestures. No getters exist.
      await am.setGestures({ rotate: false, pitch: false });
      await am.setPadding({ top: 8, left: 8, right: 8, bottom: 8 });
      await am.setGestures({ scroll: true, zoom: true, rotate: true, pitch: true });
      return 'resolved (no getters)';
    });

    await step('setCamera bearing/tilt', async () => {
      // Rotate + tilt the camera, read it back, then reset to north-up / top-down.
      await am.setCamera({ coordinate: center, zoom: 15, bearing: 45, angle: 30, animate: false });
      const turned = await am.getCameraPosition();
      await am.setCamera({ coordinate: center, zoom: 12, bearing: 0, angle: 0, animate: false });
      const reset = await am.getCameraPosition();
      check(
        near(reset.latitude, center.lat, 0.001) && near(reset.longitude, center.lng, 0.001),
        `camera at ${reset.latitude.toFixed(4)},${reset.longitude.toFixed(4)} after setCamera`,
      );
      check(near(turned.bearing, 45, 1), `bearing ${turned.bearing.toFixed(1)}, expected 45`);
      check(near(turned.angle, 30, 1), `tilt ${turned.angle.toFixed(1)}, expected 30`);
      check(near(reset.bearing, 0, 1) || near(reset.bearing, 360, 1), `reset bearing ${reset.bearing.toFixed(1)}`);
      check(near(reset.angle, 0, 1), `reset tilt ${reset.angle.toFixed(1)}`);
      return '45°/30° → 0°/0°';
    });

    await step('marker style (opacity/tint/z)', async () => {
      // Opacity applies to any marker; tint recolors the default pin. No getter.
      await am.updateMarkers([
        { markerId: 'sf', opacity: 0.5, tintColor: { r: 220, g: 40, b: 40, a: 255 }, zIndex: 10 },
      ]);
      await am.updateMarkers([{ markerId: 'sf', opacity: 1, tintColor: null, zIndex: 0 }]);
      return 'resolved (no getter)';
    });

    await step('dashed + geodesic polyline', async () => {
      // A great-circle SF→NYC line, dashed. Geodesic curvature is visible over
      // this distance where a straight screen line would not be.
      const ids = await am.addPolylines([
        {
          path: [center, { lat: 40.7128, lng: -74.006 }],
          strokeColor: '#f59e0b',
          strokeWeight: 3,
          lineDashPattern: [8, 4],
          geodesic: true,
        },
      ]);
      checkIds(ids, 1);
      overlayIds = [...overlayIds, ...ids];
      return '1 id (SF→NYC)';
    });

    await step('clustering toggle', async () => {
      // The SF trio clusters from create; toggle off and back on with a min size.
      await am.disableClustering();
      await am.enableClustering(2);
      return 'resolved (off → on, min 2)';
    });

    await step('selectMarker + deselectMarker', async () => {
      // Programmatically open the standalone pin's info window, then close it.
      await am.selectMarker('info-demo');
      await am.deselectMarker();
      return 'ok';
    });

    await step('setCameraBoundary', async () => {
      // With a boundary set, moving the camera far outside it must leave the
      // center inside; once cleared, the same move must go through.
      const box = markerBounds();
      const nyc = { lat: 40.7128, lng: -74.006 };
      await am.setCameraBoundary(box);
      await am.setCamera({ coordinate: nyc, zoom: 12, animate: false });
      const held = await am.getCameraPosition();
      await am.setCameraBoundary(null);
      await am.setCamera({ coordinate: nyc, zoom: 12, animate: false });
      const freed = await am.getCameraPosition();
      await am.setCamera({ coordinate: center, zoom: 12, animate: false });
      const heldAt = { lat: held.latitude, lng: held.longitude };
      check(
        contains(box, heldAt, 0.01),
        `center escaped the boundary: ${heldAt.lat.toFixed(3)},${heldAt.lng.toFixed(3)}`,
      );
      check(near(freed.latitude, nyc.lat, 0.05) && near(freed.longitude, nyc.lng, 0.05), 'cleared boundary still held');
      return 'held → cleared';
    });

    await step('buildings toggle', async () => {
      await am.setBuildingsEnabled(false);
      await am.setBuildingsEnabled(true);
      return 'resolved (no getter)';
    });

    await step('user tracking', async () => {
      // Show the native recenter/follow button; 'follow' needs location permission
      // to actually move the camera but is harmless without it.
      await am.setUserTrackingButtonVisible(true);
      await am.setUserTrackingMode('follow');
      await am.setUserTrackingMode('none');
      return 'resolved (button shown; follow → none)';
    });

    await step('takeSnapshot', async () => {
      const image = await am.takeSnapshot();
      check(image.startsWith('data:image/png;base64,'), 'not a PNG data URL');
      const pixels = await readSnapshot(image);
      const rect = element!.getBoundingClientRect();
      const expected = rect.width / rect.height;
      const actual = pixels.width / pixels.height;
      check(near(actual, expected, expected * 0.03), `aspect ${actual.toFixed(3)}, map is ${expected.toFixed(3)}`);
      return `${pixels.width}×${pixels.height}, ${Math.round(image.length / 1024)} KB`;
    });

    await step('remote icon (shared url)', async () => {
      // Two pins sharing one https icon, both on screen while it downloads: every
      // pin using the url must get the image, not just the first to request it.
      // Read back from snapshot pixels at each pin. Needs network.
      const spot = { lat: 37.72, lng: -122.47 }; // clear of the other pins
      const offset = 0.01; // pins sit this many degrees either side of the center
      await am.disableClustering();
      await am.setCamera({ coordinate: spot, zoom: 14, bearing: 0, angle: 0, animate: false });
      const ids = await am.addMarkers(
        [-offset, offset].map((d, i) => ({
          markerId: `remote-${i}`,
          coordinate: { lat: spot.lat, lng: spot.lng + d },
          iconUrl: REMOTE_ICON_URL,
          iconSize: { width: 32, height: 32 },
          iconAnchor: { x: 0.5, y: 0.5 },
        })),
      );
      try {
        const bounds = await am.getMapBounds();
        const span = bounds.northeast.lng - bounds.southwest.lng;
        const isMagenta = (r: number, g: number, b: number) => r > 200 && g < 80 && b > 200;
        let found: boolean[] = [false, false];
        for (let attempt = 0; attempt < 16 && !found.every(Boolean); attempt++) {
          await sleep(500);
          const pixels = await readSnapshot(await am.takeSnapshot());
          found = [-offset, offset].map((d) => {
            const x = ((spot.lng + d - bounds.southwest.lng) / span) * pixels.width;
            return pixels.anyNear(x, pixels.height / 2, 6, isMagenta);
          });
        }
        check(found.every(Boolean), `icon drawn on pins: ${found.map((f, i) => `${i}:${f ? 'yes' : 'no'}`).join(' ')}`);
        return 'both pins show the downloaded icon';
      } finally {
        await am.removeMarkers(ids);
        await am.enableClustering(2);
        await am.setCamera({ coordinate: center, zoom: 12, animate: false });
      }
    });

    // ── Search + geocoding (network) ──
    const searchRegion = { latitude: center.lat, longitude: center.lng, latitudeDelta: 0.2, longitudeDelta: 0.2 };

    await step('geocode', async () => {
      // CLGeocoder matches addresses, not landmark names: City Hall's street address.
      const address = '1 Dr Carlton B Goodlett Pl, San Francisco, CA 94102';
      const result = await geocode({ address });
      check(result.latitude !== undefined && result.longitude !== undefined, `no match for "${address}"`);
      check(near(result.latitude, center.lat, 0.05) && near(result.longitude, center.lng, 0.05), 'not near City Hall');
      return `${result.latitude.toFixed(4)},${result.longitude.toFixed(4)}`;
    });

    await step('reverseGeocode', async () => {
      const result = await reverseGeocode({ latitude: center.lat, longitude: center.lng });
      check(result.locality === 'San Francisco', `locality ${result.locality ?? '(none)'}`);
      return result.address ?? result.locality;
    });

    await step('searchPlaces', async () => {
      const { results } = await searchPlaces({ query: 'coffee', region: searchRegion, limit: 5 });
      check(results.length >= 1 && results.length <= 5, `${results.length} results, expected 1–5`);
      const far = results.filter((r) => !near(r.latitude, center.lat, 0.3) || !near(r.longitude, center.lng, 0.3));
      check(far.length === 0, `outside the region: ${far.map((r) => r.title).join(', ')}`);
      return `${results.length} results, e.g. ${results[0].title}`;
    });

    await step('searchAutocomplete + searchResolve', async () => {
      const { results } = await searchAutocomplete({ query: 'Golden Gate Park', region: searchRegion });
      check(results.length > 0, 'no suggestions');
      const place = await searchResolve({ id: results[0].id });
      check(place.lat !== undefined && place.lng !== undefined, 'suggestion did not resolve to coordinates');
      check(near(place.lat, center.lat, 0.3) && near(place.lng, center.lng, 0.3), 'resolved outside the Bay Area');
      return `${results[0].title} → ${place.lat.toFixed(3)},${place.lng.toFixed(3)}`;
    });
  }

  // ── Google smoke sequence ─────────────────────────────────────────────────
  // The same exercise against GoogleMap. Steps line up with the Apple list;
  // where Google's native API has no equivalent the step name says "(n/a on
  // Google)" so the two checklists read side by side.
  async function runGoogleSmokeSequence(gm: GoogleMap) {
    await step('getMapType', async () => {
      // Google has no getCameraPosition; getMapType is the closest read-back.
      const type = await gm.getMapType();
      return `${type}`;
    });

    await step('addPolylines', async () => {
      const ids = await gm.addPolylines([
        { path: markers.map((m) => m.coordinate), strokeColor: '#2563eb', strokeWeight: 4, strokeOpacity: 0.9 },
      ]);
      checkIds(ids, 1);
      googleOverlays = { ...googleOverlays, polylines: [...googleOverlays.polylines, ...ids] };
      return '1 id';
    });

    await step('addPolygons', async () => {
      const ids = await gm.addPolygons([
        {
          paths: markers.map((m) => m.coordinate),
          strokeColor: '#2563eb',
          strokeWeight: 2,
          fillColor: '#3b82f6',
          fillOpacity: 0.2,
        },
      ]);
      checkIds(ids, 1);
      googleOverlays = { ...googleOverlays, polygons: [...googleOverlays.polygons, ...ids] };
      return '1 id';
    });

    await step('addCircles', async () => {
      const ids = await gm.addCircles([
        { center, radius: 1500, strokeColor: '#2563eb', fillColor: '#3b82f6', fillOpacity: 0.2 },
      ]);
      checkIds(ids, 1);
      googleOverlays = { ...googleOverlays, circles: [...googleOverlays.circles, ...ids] };
      return '1 id';
    });

    await step('fitBounds', async () => {
      // Google's fitBounds takes a LatLngBounds + pixel padding (no animate flag).
      await gm.fitBounds(new LatLngBounds(markerBounds()), 48);
      return 'ok';
    });

    await step('addMarker + removeMarker', async () => {
      const id = await gm.addMarker({
        coordinate: { lat: center.lat - 0.02, lng: center.lng - 0.02 },
        title: 'Temp pin',
      });
      checkIds([id], 1);
      await gm.removeMarker(id);
      return `id ${id.slice(0, 8)}…`;
    });

    // Google has no updateMarkers; the draggable 'wharf' pin gets its flag at
    // create time instead, and drag events are wired up in onMount.
    steps = [...steps, { name: 'updateMarkers (n/a on Google)', ok: true, detail: 'set at create' }];

    await step('clustering toggle', async () => {
      // Apple's "appearance toggles" step has no Google analogue; exercise the
      // clustering API instead (also what makes the cluster listener fire).
      await gm.disableClustering();
      await gm.enableClustering(2);
      return 'off → on';
    });

    await step('traffic + indoor toggle', async () => {
      // The subset of appearance setters Google exposes; restore both after.
      await gm.enableTrafficLayer(true);
      await gm.enableIndoorMaps(true);
      await gm.enableIndoorMaps(false);
      await gm.enableTrafficLayer(false);
      return 'traffic/indoor';
    });

    await step('padding', async () => {
      // Google has setPadding but no granular gesture setter (only enable/
      // disableTouch, which is all-or-nothing), so pan/zoom stay on.
      await gm.setPadding({ top: 8, left: 8, right: 8, bottom: 8 });
      return 'ok';
    });

    // Google has no takeSnapshot.
    steps = [...steps, { name: 'takeSnapshot (n/a on Google)', ok: true, detail: '—' }];
  }

  // ── Apple control-bar actions ─────────────────────────────────────────────
  async function toggleMapType() {
    if (!appleMap) return;
    try {
      await appleMap.setMapType(satellite ? 'standard' : 'hybrid');
      satellite = !satellite;
      note = satellite ? 'satellite view' : 'standard view';
    } catch (err) {
      note = `setMapType failed: ${errMsg(err)}`;
    }
  }

  async function fitBoundsButton() {
    if (!appleMap) return;
    try {
      await appleMap.fitBounds(markerBounds(), 48, true);
      note = 'fit bounds';
    } catch (err) {
      note = `fitBounds failed: ${errMsg(err)}`;
    }
  }

  async function clearOverlays() {
    if (!appleMap || overlayIds.length === 0) return;
    try {
      await appleMap.removeOverlays(overlayIds);
      note = `cleared ${overlayIds.length} overlays`;
      overlayIds = [];
    } catch (err) {
      note = `removeOverlays failed: ${errMsg(err)}`;
    }
  }

  async function myLocation() {
    if (!appleMap) return;
    try {
      // Prompt for location permission (0.5.6), then show the blue dot. The app's
      // Info.plist still needs NSLocationWhenInUseUsageDescription for the prompt.
      const status = await requestPermissions();
      await appleMap.enableCurrentLocation(true);
      note = `current location enabled (permission: ${status.location})`;
    } catch (err) {
      note = `enableCurrentLocation failed: ${errMsg(err)}`;
    }
  }

  // Follow the device location, and show the native recenter/follow button (0.7.0).
  async function trackMe() {
    if (!appleMap) return;
    try {
      await requestPermissions();
      await appleMap.setUserTrackingButtonVisible(true);
      await appleMap.setUserTrackingMode('follow');
      note = 'tracking: follow';
    } catch (err) {
      note = `setUserTrackingMode failed: ${errMsg(err)}`;
    }
  }

  async function toggleTraffic() {
    if (!appleMap) return;
    try {
      await appleMap.setTrafficEnabled(!traffic);
      traffic = !traffic;
      note = traffic ? 'traffic on' : 'traffic off';
    } catch (err) {
      note = `setTrafficEnabled failed: ${errMsg(err)}`;
    }
  }

  async function toggleColorScheme() {
    if (!appleMap) return;
    try {
      await appleMap.setColorScheme(dark ? 'default' : 'dark');
      dark = !dark;
      note = dark ? 'dark map' : 'system map';
    } catch (err) {
      note = `setColorScheme failed: ${errMsg(err)}`;
    }
  }

  // ── Google control-bar actions ────────────────────────────────────────────
  // Same buttons as iOS, minus "Dark" — Google's native plugin has no runtime
  // color-scheme setter (dark styling is a create-time `styles`/`mapId` option).
  async function gToggleMapType() {
    if (!googleMap) return;
    try {
      await googleMap.setMapType(satellite ? MapType.Normal : MapType.Hybrid);
      satellite = !satellite;
      note = satellite ? 'satellite view' : 'standard view';
    } catch (err) {
      note = `setMapType failed: ${errMsg(err)}`;
    }
  }

  async function gToggleTraffic() {
    if (!googleMap) return;
    try {
      await googleMap.enableTrafficLayer(!traffic);
      traffic = !traffic;
      note = traffic ? 'traffic on' : 'traffic off';
    } catch (err) {
      note = `enableTrafficLayer failed: ${errMsg(err)}`;
    }
  }

  async function gFitBounds() {
    if (!googleMap) return;
    try {
      await googleMap.fitBounds(new LatLngBounds(markerBounds()), 48);
      note = 'fit bounds';
    } catch (err) {
      note = `fitBounds failed: ${errMsg(err)}`;
    }
  }

  async function gClearOverlays() {
    if (!googleMap || googleOverlayCount === 0) return;
    try {
      const { polylines, polygons, circles } = googleOverlays;
      if (polylines.length) await googleMap.removePolylines(polylines);
      if (polygons.length) await googleMap.removePolygons(polygons);
      if (circles.length) await googleMap.removeCircles(circles);
      note = `cleared ${googleOverlayCount} overlays`;
      googleOverlays = { polylines: [], polygons: [], circles: [] };
    } catch (err) {
      note = `remove overlays failed: ${errMsg(err)}`;
    }
  }

  async function gMyLocation() {
    if (!googleMap) return;
    try {
      // On Android this needs the location permission in the manifest to show
      // the blue dot; the call itself is harmless without it.
      await googleMap.enableCurrentLocation(true);
      note = 'current location enabled';
    } catch (err) {
      note = `enableCurrentLocation failed: ${errMsg(err)}`;
    }
  }

  onMount(async () => {
    if (isAndroid) document.documentElement.classList.add('android-underlay');
    if (needsKey || !element) return;
    try {
      // create() waits for the element's layout internally, so there's nothing
      // to poll for here. forceCreate rebuilds the native view for this id
      // rather than reusing a stale one from a previous mount.
      if (isIOS) {
        appleMap = await AppleMap.create({
          id: 'map',
          element,
          config: {
            center,
            zoom: 11,
            minZoom: 3,
            maxZoom: 18,
            clustering: true,
            showInfoWindows: true,
            // Exercise the create-time appearance path (the runtime setters are
            // covered by the smoke sequence and the control-bar buttons).
            showsScale: true,
          },
          forceCreate: true,
        });
        map = appleMap;

        // No iconUrl needed — each provider draws its own default pin.
        const markerIds = await appleMap.addMarkers(markers);

        // Report every gesture through the single `note` string.
        await appleMap.setOnMarkerClickListener((data) => {
          note = `tapped ${data.title || data.markerId}`;
        });
        await appleMap.setOnInfoWindowClickListener((data) => {
          note = `info window tapped: ${data.title || data.markerId}`;
        });
        await appleMap.setOnMapClickListener((data) => {
          note = `map click @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });
        await appleMap.setOnMapLongClickListener((data) => {
          note = `long-press @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });
        await appleMap.setOnClusterClickListener((data) => {
          note = `cluster ×${data.count}`;
        });
        await appleMap.setOnCameraMoveStartedListener((data) => {
          note = data.isGesture ? 'camera move (gesture)' : 'camera move (programmatic)';
        });

        // Draggable-marker events (the 'wharf' pin opted in via `draggable`).
        await appleMap.setOnMarkerDragStartListener((data) => {
          note = `drag start ${data.markerId}`;
        });
        await appleMap.setOnMarkerDragListener((data) => {
          note = `dragging @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });
        await appleMap.setOnMarkerDragEndListener((data) => {
          note = `drag end @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });

        // Overlay-tap listeners (0.6.0) — fire on the overlays the smoke run adds.
        // Apple now matches Google's overlay-click events.
        await appleMap.setOnPolylineClickListener((data) => {
          note = `polyline tapped ${data.polylineId.slice(0, 8)}…`;
        });
        await appleMap.setOnPolygonClickListener((data) => {
          note = `polygon tapped ${data.polygonId.slice(0, 8)}…`;
        });
        await appleMap.setOnCircleClickListener((data) => {
          note = `circle tapped ${data.circleId.slice(0, 8)}…`;
        });
        // Tap on the blue user-location dot (0.6.0).
        await appleMap.setOnMyLocationClickListener((data) => {
          note = `my location tapped @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });

        // Kick off the automatic smoke sequence.
        await runAppleSmokeSequence(appleMap, markerIds);
      } else {
        googleMap = await GoogleMap.create({
          id: 'map',
          element,
          apiKey: googleKey,
          config: { center, zoom: 11, minZoom: 3, maxZoom: 18 },
          forceCreate: true,
        });
        map = googleMap;

        // No iconUrl needed — each provider draws its own default pin.
        await googleMap.addMarkers(markers);
        // Mirror the Apple map's `clustering: true`. minClusterSize 2 makes the
        // nearby SF pins cluster at zoom 11 so the cluster listener has something
        // to fire on. Zoom in to separate (and to drag the 'wharf' pin).
        await googleMap.enableClustering(2);

        // The same listeners as iOS, reporting through the single `note` string.
        // Google exposes extra overlay-click listeners and no map long-press.
        await googleMap.setOnMarkerClickListener((data) => {
          note = `tapped ${data.title || data.markerId}`;
        });
        await googleMap.setOnInfoWindowClickListener((data) => {
          note = `info window tapped: ${data.title || data.markerId}`;
        });
        await googleMap.setOnMapClickListener((data) => {
          note = `map click @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });
        // Google has no onMapLongClick; that listener is iOS-only.
        await googleMap.setOnClusterClickListener((data) => {
          note = `cluster ×${data.size}`;
        });
        await googleMap.setOnCameraMoveStartedListener((data) => {
          note = data.isGesture ? 'camera move (gesture)' : 'camera move (programmatic)';
        });

        // Overlay-click listeners (Google draws these; the smoke run adds the
        // overlays they fire on).
        await googleMap.setOnPolylineClickListener((data) => {
          note = `polyline tapped ${data.polylineId.slice(0, 8)}…`;
        });
        await googleMap.setOnPolygonClickListener((data) => {
          note = `polygon tapped ${data.polygonId.slice(0, 8)}…`;
        });
        await googleMap.setOnCircleClickListener((data) => {
          note = `circle tapped ${data.circleId.slice(0, 8)}…`;
        });

        // Draggable-marker events (the 'wharf' pin opted in via `draggable`).
        await googleMap.setOnMarkerDragStartListener((data) => {
          note = `drag start ${data.markerId}`;
        });
        await googleMap.setOnMarkerDragListener((data) => {
          note = `dragging @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });
        await googleMap.setOnMarkerDragEndListener((data) => {
          note = `drag end @ ${data.latitude.toFixed(3)},${data.longitude.toFixed(3)}`;
        });

        // Kick off the automatic smoke sequence.
        await runGoogleSmokeSequence(googleMap);
      }
    } catch (err) {
      note = `map error: ${errMsg(err)}`;
    }
  });

  onDestroy(() => {
    void map?.destroy();
  });
</script>

<div class="app">
  <header>
    <h1>capacitor-plugin-apple-maps</h1>
    <p><strong>{provider}</strong>{note ? ` · ${note}` : ''}</p>
  </header>

  {#if needsKey}
    <div class="notice">
      <p>Set <code>VITE_GOOGLE_MAPS_API_KEY</code> (and the AndroidManifest key) to show Google Maps.</p>
      <p>iOS needs no key — run it there to see Apple Maps.</p>
    </div>
  {:else}
    <div class="map-wrap">
      {#if isIOS}
        <capacitor-apple-map bind:this={element} id="map" class="map"></capacitor-apple-map>
      {:else}
        <capacitor-google-map bind:this={element} id="map" class="map"></capacitor-google-map>
      {/if}

      <!-- Control bar: every button calls the plugin and reports via `note`.
           Both providers share the bar; Apple adds a "Dark" toggle it alone
           supports at runtime. -->
      <div class="controls">
        {#if isIOS}
          <button onclick={toggleMapType}>{satellite ? 'Standard' : 'Satellite'}</button>
          <button onclick={toggleTraffic}>{traffic ? 'Traffic off' : 'Traffic'}</button>
          <button onclick={toggleColorScheme}>{dark ? 'System' : 'Dark'}</button>
          <button onclick={fitBoundsButton}>Fit bounds</button>
          <button onclick={clearOverlays} disabled={overlayIds.length === 0}>Clear overlays</button>
          <button onclick={myLocation}>My location</button>
          <button onclick={trackMe}>Track</button>
        {:else}
          <button onclick={gToggleMapType}>{satellite ? 'Standard' : 'Satellite'}</button>
          <button onclick={gToggleTraffic}>{traffic ? 'Traffic off' : 'Traffic'}</button>
          <button onclick={gFitBounds}>Fit bounds</button>
          <button onclick={gClearOverlays} disabled={googleOverlayCount === 0}>Clear overlays</button>
          <button onclick={gMyLocation}>My location</button>
        {/if}
      </div>

      <!-- Smoke-test checklist + latest gesture note, translucent over the map. -->
      <div class="panel">
        <ul class="steps">
          {#each steps as s, i (i)}
            <li class:fail={!s.ok}>
              <span class="mark">{s.ok ? '✓' : '✗'}</span>
              <span class="step-name">{s.name}</span>
              <span class="detail">{s.detail}</span>
            </li>
          {/each}
        </ul>
        {#if note}
          <p class="note">{note}</p>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  :global(html, body) {
    margin: 0;
    height: 100%;
    background: #0b1020;
  }
  /* Android renders the Google map behind the webview — the page above it must
     be transparent for the map to show through. */
  :global(html.android-underlay),
  :global(html.android-underlay body) {
    background: transparent;
  }
  .app {
    display: flex;
    flex-direction: column;
    height: 100dvh;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  }
  header {
    padding: max(env(safe-area-inset-top), 14px) 16px 12px;
    color: #fff;
    background: #405ec9;
  }
  h1 {
    margin: 0;
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.01em;
  }
  header p {
    margin: 2px 0 0;
    font-size: 13px;
    opacity: 0.9;
  }
  /* Holds the map plus the overlays; the map still fills all of it. */
  .map-wrap {
    position: relative;
    flex: 1;
    display: flex;
  }
  .map {
    flex: 1;
    display: block;
    width: 100%;
  }
  .controls {
    position: absolute;
    top: 12px;
    left: 12px;
    right: 12px;
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    z-index: 2;
  }
  .controls button {
    padding: 8px 12px;
    font-size: 13px;
    font-weight: 600;
    color: #eaf0ff;
    background: rgba(20, 30, 62, 0.82);
    border: 1px solid rgba(120, 150, 230, 0.5);
    border-radius: 999px;
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
    cursor: pointer;
  }
  .controls button:active {
    background: rgba(64, 94, 201, 0.9);
  }
  .controls button:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .panel {
    position: absolute;
    left: 12px;
    right: 12px;
    bottom: max(env(safe-area-inset-bottom), 12px);
    max-height: 42%;
    overflow-y: auto;
    padding: 10px 12px;
    color: #dbe4ff;
    background: rgba(11, 16, 32, 0.78);
    border: 1px solid rgba(120, 150, 230, 0.35);
    border-radius: 12px;
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    z-index: 2;
  }
  .steps {
    margin: 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .steps li {
    display: flex;
    align-items: baseline;
    gap: 8px;
    font-size: 13px;
  }
  .mark {
    color: #4ade80;
    font-weight: 700;
  }
  .steps li.fail .mark {
    color: #f87171;
  }
  .step-name {
    font-weight: 600;
  }
  .detail {
    margin-left: auto;
    opacity: 0.75;
    font-variant-numeric: tabular-nums;
  }
  .note {
    margin: 8px 0 0;
    padding-top: 8px;
    border-top: 1px solid rgba(120, 150, 230, 0.25);
    font-size: 13px;
    color: #aab8e6;
  }
  .notice {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 10px;
    padding: 0 28px;
    color: #c7d0e8;
    font-size: 15px;
    line-height: 1.5;
    text-align: center;
  }
  .notice code {
    color: #fff;
    font-size: 13px;
  }
</style>
