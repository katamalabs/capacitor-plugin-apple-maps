# Example: Apple Maps + Google Maps, one API

A deliberately tiny [Svelte](https://svelte.dev) + Capacitor app showing the
whole point of this plugin: **iOS renders Apple Maps (MapKit), Android and web
render Google Maps, from one shared API.**

The entire app is [`src/App.svelte`](src/App.svelte). It branches on platform
only to pick the provider — after that both sides run the **same feature set**:

```ts
const isIOS = Capacitor.getPlatform() === 'ios';

map = isIOS
  ? await AppleMap.create({ id: 'map', element, config: { center, zoom: 11 } })
  : await GoogleMap.create({ id: 'map', element, apiKey: googleKey, config: { center, zoom: 11 } });

await map.addMarkers([{ coordinate: center, title: 'San Francisco' }]);
await map.setOnMarkerClickListener((data) => (tapped = data.title ?? data.markerId));
```

Both providers get the **same demo**: a control bar (map type, traffic, fit
bounds, clear overlays, my location), a draggable pin, polyline / polygon /
circle overlays, marker / info-window / map / overlay / cluster / camera / drag
listeners, and an automatic ✓/✗ smoke checklist that touches each API once.

The markers pass **no `iconUrl`** — each provider draws its own default pin
(Apple Maps does this as of plugin 0.3.2).

**Where Google does less.** A few Apple/MapKit methods have no native Google
equivalent, so the Google branch skips them (and the checklist marks them
`n/a on Google`): a runtime color-scheme (Dark) toggle, map long-press,
`updateMarkers` (the draggable pin gets its flag at create time instead),
`takeSnapshot`, and granular gesture / POI / compass / scale setters.

## Run it

```bash
npm install
```

### iOS — Apple Maps, no API key needed

```bash
npm run sim:ios                              # build + boot a simulator (picker)
npm run targets:ios                          # list simulators + IDs
npm run sim:ios -- --target <simulator-id>   # boot a specific one
npm run ios                                  # build + open Xcode
```

### Android / web — Google Maps, needs a key

Google Maps needs an API key (enable _Maps SDK for Android_ and _Maps JavaScript
API_ for it). Without one the app shows a hint instead of a map — it never
crashes.

Set it in **one place**: copy `.env.example` to `.env` and set
`VITE_GOOGLE_MAPS_API_KEY`. `.env` is gitignored, so the key never lands in a
committed file. The Android build reads the same `.env`
(`android/app/build.gradle` copies it into the manifest's
`com.google.android.geo.API_KEY`), so there's nothing to set in `gradle.properties`.

```bash
npm start                                        # web dev server
npm run sim:android                              # build + boot the emulator
npm run sim:android -- --target <emulator-id>    # a specific one (targets:android to list)
npm run android                                  # build + open Android Studio
```
