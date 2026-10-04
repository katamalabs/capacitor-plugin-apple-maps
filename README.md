# capacitor-plugin-apple-maps

[![npm version](https://img.shields.io/npm/v/capacitor-plugin-apple-maps.svg)](https://www.npmjs.com/package/capacitor-plugin-apple-maps)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->

[![All Contributors](https://img.shields.io/badge/all_contributors-1-orange.svg?style=flat-square)](#contributors-)

<!-- ALL-CONTRIBUTORS-BADGE:END -->

Renders a **native Apple Maps (MapKit)** view on iOS from a Capacitor app. The
`AppleMap` wrapper class deliberately mirrors
[`@capacitor/google-maps`](https://github.com/ionic-team/capacitor-plugins/tree/main/google-maps)'
`GoogleMap` API - camera control, markers, clustering, shape overlays, place
search, and the map/marker/camera events - so an app can route **iOS to Apple
Maps and Android/web to Google Maps** behind one thin abstraction.

- **iOS only.** MapKit is a native iOS framework and needs no API key or usage
  billing (shipping to the App Store still needs the standard Apple Developer
  Program membership, as with any iOS app). On web and Android every method
  rejects with `unavailable` - the host app is expected to use another provider
  on those platforms.
- **No external dependencies.** Uses the system `MapKit` framework; the only SPM
  dependency is `capacitor-swift-pm`.
- Requires **iOS 15+** (matches the Capacitor 8 baseline).

## Features

- **Camera** - `setCamera`, `getCameraPosition`, `getMapBounds`, and
  `fitBounds` (from a `LatLngBounds` or a raw `LatLng[]`), with approximated
  Google-style zoom and a `minZoom` floor.
- **Markers** - add/update/remove (batch or single), custom icons, stable
  caller ids, draggable pins, clustering, and optional info-window bubbles.
- **Shape overlays** - polylines, polygons (with holes), and circles, removable
  by id.
- **Place search** - keyless `MKLocalSearch` / `MKLocalSearchCompleter`
  autocomplete, one-shot search, and coordinate resolution.
- **Appearance & controls** - map type, traffic, points of interest, compass,
  scale, forced color scheme, per-gesture toggles, and edge padding.
- **Events** - camera idle / move-started, marker click, info-window click,
  map click / long-click, cluster click, and marker drag start/move/end.
- **`takeSnapshot`** - render the visible map (pins + overlays) to a PNG
  `data:` URL.

## Install

```bash
npm install capacitor-plugin-apple-maps
npx cap sync ios
```

## Usage

Bind the map to a `<capacitor-apple-map>` element (registered automatically when
you import the wrapper):

```html
<capacitor-apple-map id="map" style="position:absolute; inset:0"></capacitor-apple-map>
```

```ts
import { AppleMap } from 'capacitor-plugin-apple-maps';

const map = await AppleMap.create({
  id: 'map',
  element: document.getElementById('map')!,
  config: {
    center: { lat: 42.36, lng: -71.06 },
    zoom: 11,
    minZoom: 7,
  },
});

await map.setOnMarkerClickListener((data) => console.log('tapped', data.markerId));
await map.setOnCameraIdleListener((data) => console.log('idle at', data.zoom, data.bounds));

const ids = await map.addMarkers([
  { coordinate: { lat: 42.36, lng: -71.06 }, iconUrl: 'marker-blue.png', iconSize: { width: 30, height: 36 } },
]);
await map.enableClustering();
```

A marker with **no `iconUrl`** draws MapKit's native pin
(`MKMarkerAnnotationView`), the same way `@capacitor/google-maps` falls back to a
default marker - so a marker written against the shared API is always visible.
Supply an `iconUrl` to use your own art, resolved from three sources: a **bundled
web asset** filename (copied into the app bundle under `public/` - e.g.
`marker-blue.png` from your web `static/`), an **`https:` URL**, or a **`data:`
URI**. SVG is not supported.

By default an icon is anchored by its **bottom centre**, so a teardrop pin's tip
marks the spot. For art that should sit **centred** on the coordinate - a "you
are here" dot, a circular avatar, a square badge - pass `iconAnchor` as fractions
of the image from its top-left:

```ts
await map.addMarkers([
  { coordinate: here, iconUrl: 'you-are-here.png', iconAnchor: { x: 0.5, y: 0.5 } },
]);
```

### Overlays

```ts
const [lineId] = await map.addPolylines([
  { path: [{ lat: 42.36, lng: -71.06 }, { lat: 42.37, lng: -71.05 }], strokeColor: '#ff3b30', strokeWeight: 4 },
]);
await map.addCircles([{ center: { lat: 42.36, lng: -71.06 }, radius: 500, fillColor: '#007aff33' }]);
await map.removeOverlays([lineId]);
```

### Place search

No API key required - both use MapKit's on-device search. These are standalone
exports, not map methods (they need no map instance).

```ts
import { searchAutocomplete, searchPlaces, searchResolve } from 'capacitor-plugin-apple-maps';

// Type-ahead suggestions, then resolve one to coordinates.
const { results } = await searchAutocomplete({ query: 'coffee' });
const place = await searchResolve({ id: results[0].id });

// A "where" field: towns, postal codes and addresses, no businesses or landmarks.
const { results: towns } = await searchAutocomplete({ query: 'Charleston', resultTypes: ['address'] });

// Or a one-shot search that returns coordinates up front.
const { results: places } = await searchPlaces({ query: 'Fenway Park', limit: 5 });
```

### Geocoding

Also key-free, via `CLGeocoder`. Both resolve an empty object rather than
rejecting when nothing is found, the device is offline, or Apple's per-app rate
limit kicks in - so geocode once per user action, not per location update.

```ts
import { reverseGeocode, geocode } from 'capacitor-plugin-apple-maps';

// A device fix to a line you can show: "1 Main St, Boston MA 02110, United States".
const { address, locality } = await reverseGeocode({ latitude: 42.36, longitude: -71.06 });

// Free text to coordinates. Check `latitude` before using the result.
const place = await geocode({ address: '1 Infinite Loop, Cupertino' });
```

### Sharing one abstraction with `@capacitor/google-maps`

The wrapper's method names and payload shapes (`LatLng`, `LatLngBounds`,
`CameraIdleCallbackData`, `MarkerClickCallbackData`) match `@capacitor/google-maps`,
so a host app can pick the provider per platform:

```ts
const map =
  Capacitor.getPlatform() === 'ios'
    ? await AppleMap.create({ id, element, config })
    : await GoogleMap.create({ id, element, apiKey, config });
```

## Notes & limitations

- **Zoom is approximated.** MapKit uses region spans, not Google's integer
  zoom; the plugin converts using the web-mercator tile relationship. Reported
  zoom round-trips but is not pixel-identical to Google.
- **Cluster taps zoom to fit** the cluster members (Apple-native behaviour)
  rather than firing an event.
- `minZoom` is enforced on programmatic moves and by bouncing back a gesture
  that overshoots the floor. `maxZoom` is currently advisory.

## API

<docgen-index>

* [`checkPermissions()`](#checkpermissions)
* [`requestPermissions()`](#requestpermissions)
* [`create(...)`](#create)
* [`destroy(...)`](#destroy)
* [`setCamera(...)`](#setcamera)
* [`getMapBounds(...)`](#getmapbounds)
* [`getCameraPosition(...)`](#getcameraposition)
* [`fitBounds(...)`](#fitbounds)
* [`addMarkers(...)`](#addmarkers)
* [`addMarker(...)`](#addmarker)
* [`updateMarkers(...)`](#updatemarkers)
* [`removeMarkers(...)`](#removemarkers)
* [`removeMarker(...)`](#removemarker)
* [`enableClustering(...)`](#enableclustering)
* [`disableClustering(...)`](#disableclustering)
* [`addPolylines(...)`](#addpolylines)
* [`addPolygons(...)`](#addpolygons)
* [`addCircles(...)`](#addcircles)
* [`removeOverlays(...)`](#removeoverlays)
* [`setMapType(...)`](#setmaptype)
* [`getMapType(...)`](#getmaptype)
* [`setUserTrackingMode(...)`](#setusertrackingmode)
* [`setUserTrackingButtonVisible(...)`](#setusertrackingbuttonvisible)
* [`setBuildingsEnabled(...)`](#setbuildingsenabled)
* [`setCameraBoundary(...)`](#setcameraboundary)
* [`selectMarker(...)`](#selectmarker)
* [`deselectMarker(...)`](#deselectmarker)
* [`enableCurrentLocation(...)`](#enablecurrentlocation)
* [`setTrafficEnabled(...)`](#settrafficenabled)
* [`setPointsOfInterestEnabled(...)`](#setpointsofinterestenabled)
* [`setCompassEnabled(...)`](#setcompassenabled)
* [`setScaleEnabled(...)`](#setscaleenabled)
* [`setColorScheme(...)`](#setcolorscheme)
* [`setGestures(...)`](#setgestures)
* [`setPadding(...)`](#setpadding)
* [`takeSnapshot(...)`](#takesnapshot)
* [`searchAutocomplete(...)`](#searchautocomplete)
* [`searchPlaces(...)`](#searchplaces)
* [`searchResolve(...)`](#searchresolve)
* [`reverseGeocode(...)`](#reversegeocode)
* [`geocode(...)`](#geocode)
* [`onResize(...)`](#onresize)
* [`onDisplay(...)`](#ondisplay)
* [`onScroll(...)`](#onscroll)
* [`addListener('onCameraIdle', ...)`](#addlisteneroncameraidle-)
* [`addListener('onMarkerClick', ...)`](#addlisteneronmarkerclick-)
* [`addListener('onInfoWindowClick', ...)`](#addlisteneroninfowindowclick-)
* [`addListener('onMapReady', ...)`](#addlisteneronmapready-)
* [`addListener('onMapClick', ...)`](#addlisteneronmapclick-)
* [`addListener('onMapLongClick', ...)`](#addlisteneronmaplongclick-)
* [`addListener('onPolygonClick', ...)`](#addlisteneronpolygonclick-)
* [`addListener('onPolylineClick', ...)`](#addlisteneronpolylineclick-)
* [`addListener('onCircleClick', ...)`](#addlisteneroncircleclick-)
* [`addListener('onMyLocationClick', ...)`](#addlisteneronmylocationclick-)
* [`addListener('onClusterClick', ...)`](#addlisteneronclusterclick-)
* [`addListener('onCameraMoveStarted', ...)`](#addlisteneroncameramovestarted-)
* [`addListener('onMarkerDragStart', ...)`](#addlisteneronmarkerdragstart-)
* [`addListener('onMarkerDrag', ...)`](#addlisteneronmarkerdrag-)
* [`addListener('onMarkerDragEnd', ...)`](#addlisteneronmarkerdragend-)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Low-level bridge to the native MapKit implementation. Most callers should use
the {@link AppleMap} wrapper instead of these methods directly.

### checkPermissions()

```typescript
checkPermissions() => Promise<PermissionStatus>
```

Current location-permission status without prompting. See
{@link enableCurrentLocation}.

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

--------------------


### requestPermissions()

```typescript
requestPermissions() => Promise<PermissionStatus>
```

Prompt for location permission if it has not been decided yet, then resolve
with the resulting status. If permission was already granted or denied this
resolves immediately without prompting (iOS only prompts once). Requires the
host app's `NSLocationWhenInUseUsageDescription` Info.plist key.

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

--------------------


### create(...)

```typescript
create(options: { id: string; config: AppleMapConfig; element?: unknown; forceCreate?: boolean; }) => Promise<void>
```

Create the native map and mount it over the bound element. Resolves once the
map is actually in the view tree (`onMapReady` fires at the same point).
Rejects with code `MOUNT_FAILED` if no web-view container matching the
element appears within about a second (typically a hidden or zero-sized
element), or if the map is destroyed before it finishes mounting.

| Param         | Type                                                                                                                         |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; config: <a href="#applemapconfig">AppleMapConfig</a>; element?: unknown; forceCreate?: boolean; }</code> |

--------------------


### destroy(...)

```typescript
destroy(options: { id: string; }) => Promise<void>
```

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

--------------------


### setCamera(...)

```typescript
setCamera(options: { id: string; config: CameraConfig; }) => Promise<void>
```

| Param         | Type                                                                           |
| ------------- | ------------------------------------------------------------------------------ |
| **`options`** | <code>{ id: string; config: <a href="#cameraconfig">CameraConfig</a>; }</code> |

--------------------


### getMapBounds(...)

```typescript
getMapBounds(options: { id: string; }) => Promise<LatLngBounds>
```

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;<a href="#latlngbounds">LatLngBounds</a>&gt;</code>

--------------------


### getCameraPosition(...)

```typescript
getCameraPosition(options: { id: string; }) => Promise<CameraPosition>
```

Current camera as `{ latitude, longitude, zoom, bounds }`.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;<a href="#cameraposition">CameraPosition</a>&gt;</code>

--------------------


### fitBounds(...)

```typescript
fitBounds(options: { id: string; bounds: LatLngBounds; padding?: number; animate?: boolean; }) => Promise<void>
```

Move the camera to fit `bounds`, insetting the visible rect by `padding`
points on every side (default `0`). Animates unless `animate` is `false`.

| Param         | Type                                                                                                                |
| ------------- | ------------------------------------------------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; bounds: <a href="#latlngbounds">LatLngBounds</a>; padding?: number; animate?: boolean; }</code> |

--------------------


### addMarkers(...)

```typescript
addMarkers(options: { id: string; markers: Marker[]; }) => Promise<{ ids: string[]; }>
```

| Param         | Type                                            |
| ------------- | ----------------------------------------------- |
| **`options`** | <code>{ id: string; markers: Marker[]; }</code> |

**Returns:** <code>Promise&lt;{ ids: string[]; }&gt;</code>

--------------------


### addMarker(...)

```typescript
addMarker(options: { id: string; marker: Marker; }) => Promise<{ id: string; }>
```

Add a single marker, returning its id. Convenience over {@link addMarkers}.

| Param         | Type                                                               |
| ------------- | ------------------------------------------------------------------ |
| **`options`** | <code>{ id: string; marker: <a href="#marker">Marker</a>; }</code> |

**Returns:** <code>Promise&lt;{ id: string; }&gt;</code>

--------------------


### updateMarkers(...)

```typescript
updateMarkers(options: { id: string; markers: MarkerUpdate[]; }) => Promise<void>
```

Apply partial changes to existing markers, addressed by `markerId`.

| Param         | Type                                                  |
| ------------- | ----------------------------------------------------- |
| **`options`** | <code>{ id: string; markers: MarkerUpdate[]; }</code> |

--------------------


### removeMarkers(...)

```typescript
removeMarkers(options: { id: string; markerIds: string[]; }) => Promise<void>
```

| Param         | Type                                              |
| ------------- | ------------------------------------------------- |
| **`options`** | <code>{ id: string; markerIds: string[]; }</code> |

--------------------


### removeMarker(...)

```typescript
removeMarker(options: { id: string; markerId: string; }) => Promise<void>
```

Remove a single marker by id. Convenience over {@link removeMarkers}.

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; markerId: string; }</code> |

--------------------


### enableClustering(...)

```typescript
enableClustering(options: { id: string; minClusterSize?: number; }) => Promise<void>
```

Enable marker clustering. `minClusterSize` is a best-effort lower bound on how
many markers must be present before any clustering happens (MapKit has no
per-cluster minimum, so this gates clustering on the total marker count);
defaults to `2`.

| Param         | Type                                                  |
| ------------- | ----------------------------------------------------- |
| **`options`** | <code>{ id: string; minClusterSize?: number; }</code> |

--------------------


### disableClustering(...)

```typescript
disableClustering(options: { id: string; }) => Promise<void>
```

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

--------------------


### addPolylines(...)

```typescript
addPolylines(options: { id: string; polylines: Polyline[]; }) => Promise<{ ids: string[]; }>
```

| Param         | Type                                                |
| ------------- | --------------------------------------------------- |
| **`options`** | <code>{ id: string; polylines: Polyline[]; }</code> |

**Returns:** <code>Promise&lt;{ ids: string[]; }&gt;</code>

--------------------


### addPolygons(...)

```typescript
addPolygons(options: { id: string; polygons: Polygon[]; }) => Promise<{ ids: string[]; }>
```

| Param         | Type                                              |
| ------------- | ------------------------------------------------- |
| **`options`** | <code>{ id: string; polygons: Polygon[]; }</code> |

**Returns:** <code>Promise&lt;{ ids: string[]; }&gt;</code>

--------------------


### addCircles(...)

```typescript
addCircles(options: { id: string; circles: Circle[]; }) => Promise<{ ids: string[]; }>
```

| Param         | Type                                            |
| ------------- | ----------------------------------------------- |
| **`options`** | <code>{ id: string; circles: Circle[]; }</code> |

**Returns:** <code>Promise&lt;{ ids: string[]; }&gt;</code>

--------------------


### removeOverlays(...)

```typescript
removeOverlays(options: { id: string; ids: string[]; }) => Promise<void>
```

Remove overlays (polylines, polygons, or circles) by the ids their add call returned.

| Param         | Type                                        |
| ------------- | ------------------------------------------- |
| **`options`** | <code>{ id: string; ids: string[]; }</code> |

--------------------


### setMapType(...)

```typescript
setMapType(options: { id: string; mapType: MapType; }) => Promise<void>
```

Set the base map imagery.

| Param         | Type                                                                  |
| ------------- | --------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; mapType: <a href="#maptype">MapType</a>; }</code> |

--------------------


### getMapType(...)

```typescript
getMapType(options: { id: string; }) => Promise<{ mapType: MapType; }>
```

Read the current base map imagery.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;{ mapType: <a href="#maptype">MapType</a>; }&gt;</code>

--------------------


### setUserTrackingMode(...)

```typescript
setUserTrackingMode(options: { id: string; mode: UserTrackingMode; }) => Promise<void>
```

Follow the user's location (`follow`) or location and heading
(`followWithHeading`), or stop following (`none`). A following mode turns on
the user-location dot; the host app still needs location permission
({@link requestPermissions}).

| Param         | Type                                                                                 |
| ------------- | ------------------------------------------------------------------------------------ |
| **`options`** | <code>{ id: string; mode: <a href="#usertrackingmode">UserTrackingMode</a>; }</code> |

--------------------


### setUserTrackingButtonVisible(...)

```typescript
setUserTrackingButtonVisible(options: { id: string; visible: boolean; }) => Promise<void>
```

Show or hide a native recenter/follow button in the map's corner.

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; visible: boolean; }</code> |

--------------------


### setBuildingsEnabled(...)

```typescript
setBuildingsEnabled(options: { id: string; enabled: boolean; }) => Promise<void>
```

Show or hide extruded 3D buildings (`MKMapView.showsBuildings`).

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; enabled: boolean; }</code> |

--------------------


### setCameraBoundary(...)

```typescript
setCameraBoundary(options: { id: string; bounds?: LatLngBounds | null; }) => Promise<void>
```

Restrict panning so the camera center stays within `bounds`. Pass `null` (or
omit `bounds`) to clear the restriction.

| Param         | Type                                                                                    |
| ------------- | --------------------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; bounds?: <a href="#latlngbounds">LatLngBounds</a> \| null; }</code> |

--------------------


### selectMarker(...)

```typescript
selectMarker(options: { id: string; markerId: string; }) => Promise<void>
```

Programmatically select a marker, opening its info-window bubble (if it has a
title). Rejects if no marker has that id.

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; markerId: string; }</code> |

--------------------


### deselectMarker(...)

```typescript
deselectMarker(options: { id: string; }) => Promise<void>
```

Close any open info-window bubble.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

--------------------


### enableCurrentLocation(...)

```typescript
enableCurrentLocation(options: { id: string; enabled: boolean; }) => Promise<void>
```

Show or hide the blue user-location dot. Call {@link requestPermissions}
first to obtain location permission, and declare the
`NSLocationWhenInUseUsageDescription` Info.plist key in the host app; without
granted permission MapKit shows nothing.

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; enabled: boolean; }</code> |

--------------------


### setTrafficEnabled(...)

```typescript
setTrafficEnabled(options: { id: string; enabled: boolean; }) => Promise<void>
```

Overlay or hide live traffic conditions (`MKMapView.showsTraffic`).

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; enabled: boolean; }</code> |

--------------------


### setPointsOfInterestEnabled(...)

```typescript
setPointsOfInterestEnabled(options: { id: string; enabled: boolean; }) => Promise<void>
```

Show or hide Apple's points of interest (a `.includingAll` / `.excludingAll` filter).

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; enabled: boolean; }</code> |

--------------------


### setCompassEnabled(...)

```typescript
setCompassEnabled(options: { id: string; enabled: boolean; }) => Promise<void>
```

Show or hide the compass (`MKMapView.showsCompass`).

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; enabled: boolean; }</code> |

--------------------


### setScaleEnabled(...)

```typescript
setScaleEnabled(options: { id: string; enabled: boolean; }) => Promise<void>
```

Show or hide the scale bar (`MKMapView.showsScale`).

| Param         | Type                                           |
| ------------- | ---------------------------------------------- |
| **`options`** | <code>{ id: string; enabled: boolean; }</code> |

--------------------


### setColorScheme(...)

```typescript
setColorScheme(options: { id: string; colorScheme: MapColorScheme; }) => Promise<void>
```

Force a light/dark appearance, or `default` to follow the device setting.

| Param         | Type                                                                                    |
| ------------- | --------------------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; colorScheme: <a href="#mapcolorscheme">MapColorScheme</a>; }</code> |

--------------------


### setGestures(...)

```typescript
setGestures(options: { id: string; gestures: MapGestures; }) => Promise<void>
```

Enable or disable user gestures (only the fields you pass are changed).

| Param         | Type                                                                           |
| ------------- | ------------------------------------------------------------------------------ |
| **`options`** | <code>{ id: string; gestures: <a href="#mapgestures">MapGestures</a>; }</code> |

--------------------


### setPadding(...)

```typescript
setPadding(options: { id: string; padding: MapPadding; }) => Promise<void>
```

Inset the map's edges (shifts controls inward and pads `fitBounds`).

| Param         | Type                                                                        |
| ------------- | --------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; padding: <a href="#mappadding">MapPadding</a>; }</code> |

--------------------


### takeSnapshot(...)

```typescript
takeSnapshot(options: { id: string; }) => Promise<{ image: string; }>
```

Render the current map view to a PNG, returned as a `data:` URL - the visible
base map with the marker pins and overlays composited on top.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;{ image: string; }&gt;</code>

--------------------


### searchAutocomplete(...)

```typescript
searchAutocomplete(options: { query: string; region?: SearchRegion; resultTypes?: SearchResultType[]; }) => Promise<{ results: SearchCompletion[]; }>
```

Type-ahead place autocomplete via `MKLocalSearchCompleter`. Needs no API
key. Pass `region` to bias suggestions toward the area in view. Each result
carries an opaque `id`; pass it to {@link searchResolve} to get coordinates.

Pass `resultTypes` to choose what kinds of suggestion come back - e.g.
`['address']` for a "where" field that wants towns, postal codes and street
addresses but not airports and coffee shops. Defaults to
`['address', 'pointOfInterest']`; an empty or unrecognised list falls back
to that default rather than returning nothing.

| Param         | Type                                                                                                                 |
| ------------- | -------------------------------------------------------------------------------------------------------------------- |
| **`options`** | <code>{ query: string; region?: <a href="#searchregion">SearchRegion</a>; resultTypes?: SearchResultType[]; }</code> |

**Returns:** <code>Promise&lt;{ results: SearchCompletion[]; }&gt;</code>

--------------------


### searchPlaces(...)

```typescript
searchPlaces(options: { query: string; region?: SearchRegion; maxDistanceKm?: number; limit?: number; }) => Promise<{ results: SearchResult[]; }>
```

One-shot place search via `MKLocalSearch`. Unlike {@link searchAutocomplete}
the results carry coordinates up front. Pass `region` to scope/bias results,
`maxDistanceKm` to drop results farther than that from the region center
(e.g. a US ZIP that also exists abroad), and `limit` to cap the count.

| Param         | Type                                                                                                                       |
| ------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **`options`** | <code>{ query: string; region?: <a href="#searchregion">SearchRegion</a>; maxDistanceKm?: number; limit?: number; }</code> |

**Returns:** <code>Promise&lt;{ results: SearchResult[]; }&gt;</code>

--------------------


### searchResolve(...)

```typescript
searchResolve(options: { id: string; }) => Promise<SearchResolution>
```

Resolve a suggestion `id` (from either search method) to coordinates.
Returns an empty object if the id is unknown or has no location.

A `searchAutocomplete` id also comes back with `latitudeDelta` and
`longitudeDelta`: the span of the place itself, from MapKit's bounding
region. A street address spans a few metres and a province many degrees, so
this is how to tell "near this point" from "somewhere in this region".
Omitted for `searchPlaces` ids, whose search region bounds every result.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;<a href="#searchresolution">SearchResolution</a>&gt;</code>

--------------------


### reverseGeocode(...)

```typescript
reverseGeocode(options: { latitude: number; longitude: number; language?: string; }) => Promise<GeocodeResult>
```

Coordinates to an address via `CLGeocoder`. Needs no API key. Pass
`language` (a BCP 47 tag such as `es` or `fr-CA`) to localise the result;
it defaults to the device language.

Fails soft: no match, an offline device and Apple's rate limit all resolve
an empty object rather than rejecting. Apple throttles geocoding per app, so
call this once per user action, not on every location update.

| Param         | Type                                                                     |
| ------------- | ------------------------------------------------------------------------ |
| **`options`** | <code>{ latitude: number; longitude: number; language?: string; }</code> |

**Returns:** <code>Promise&lt;<a href="#geocoderesult">GeocodeResult</a>&gt;</code>

--------------------


### geocode(...)

```typescript
geocode(options: { address: string; language?: string; }) => Promise<GeocodeResult>
```

A typed address to coordinates via `CLGeocoder`. Needs no API key. For
type-ahead or business names prefer {@link searchAutocomplete} /
{@link searchPlaces}; this is the fallback for free text. Fails soft like
{@link reverseGeocode}: check for `latitude` before using the result.

| Param         | Type                                                 |
| ------------- | ---------------------------------------------------- |
| **`options`** | <code>{ address: string; language?: string; }</code> |

**Returns:** <code>Promise&lt;<a href="#geocoderesult">GeocodeResult</a>&gt;</code>

--------------------


### onResize(...)

```typescript
onResize(options: { id: string; mapBounds: MapBounds; }) => Promise<void>
```

Keep the native frame in sync as the element resizes.

| Param         | Type                                                                        |
| ------------- | --------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; mapBounds: <a href="#mapbounds">MapBounds</a>; }</code> |

--------------------


### onDisplay(...)

```typescript
onDisplay(options: { id: string; mapBounds: MapBounds; }) => Promise<void>
```

Re-mount the native view after the element becomes visible again.

| Param         | Type                                                                        |
| ------------- | --------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; mapBounds: <a href="#mapbounds">MapBounds</a>; }</code> |

--------------------


### onScroll(...)

```typescript
onScroll(options: { id: string; mapBounds: MapBounds; }) => Promise<void>
```

Keep the native frame in sync as the page scrolls (no-op on iOS).

| Param         | Type                                                                        |
| ------------- | --------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; mapBounds: <a href="#mapbounds">MapBounds</a>; }</code> |

--------------------


### addListener('onCameraIdle', ...)

```typescript
addListener(eventName: 'onCameraIdle', listenerFunc: (data: CameraIdleCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onCameraIdle'</code>                                                                  |
| **`listenerFunc`** | <code>(data: <a href="#cameraidlecallbackdata">CameraIdleCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMarkerClick', ...)

```typescript
addListener(eventName: 'onMarkerClick', listenerFunc: (data: MarkerClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                           |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMarkerClick'</code>                                                                   |
| **`listenerFunc`** | <code>(data: <a href="#markerclickcallbackdata">MarkerClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onInfoWindowClick', ...)

```typescript
addListener(eventName: 'onInfoWindowClick', listenerFunc: (data: MarkerClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                           |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onInfoWindowClick'</code>                                                               |
| **`listenerFunc`** | <code>(data: <a href="#markerclickcallbackdata">MarkerClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMapReady', ...)

```typescript
addListener(eventName: 'onMapReady', listenerFunc: (data: MapReadyCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMapReady'</code>                                                                |
| **`listenerFunc`** | <code>(data: <a href="#mapreadycallbackdata">MapReadyCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMapClick', ...)

```typescript
addListener(eventName: 'onMapClick', listenerFunc: (data: MapClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMapClick'</code>                                                                |
| **`listenerFunc`** | <code>(data: <a href="#mapclickcallbackdata">MapClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMapLongClick', ...)

```typescript
addListener(eventName: 'onMapLongClick', listenerFunc: (data: MapLongClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMapLongClick'</code>                                                            |
| **`listenerFunc`** | <code>(data: <a href="#mapclickcallbackdata">MapClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onPolygonClick', ...)

```typescript
addListener(eventName: 'onPolygonClick', listenerFunc: (data: PolygonClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| **`eventName`**    | <code>'onPolygonClick'</code>                                                                    |
| **`listenerFunc`** | <code>(data: <a href="#polygonclickcallbackdata">PolygonClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onPolylineClick', ...)

```typescript
addListener(eventName: 'onPolylineClick', listenerFunc: (data: PolylineClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                               |
| ------------------ | -------------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onPolylineClick'</code>                                                                     |
| **`listenerFunc`** | <code>(data: <a href="#polylineclickcallbackdata">PolylineClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onCircleClick', ...)

```typescript
addListener(eventName: 'onCircleClick', listenerFunc: (data: CircleClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                           |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onCircleClick'</code>                                                                   |
| **`listenerFunc`** | <code>(data: <a href="#circleclickcallbackdata">CircleClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMyLocationClick', ...)

```typescript
addListener(eventName: 'onMyLocationClick', listenerFunc: (data: MyLocationClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMyLocationClick'</code>                                                         |
| **`listenerFunc`** | <code>(data: <a href="#mapclickcallbackdata">MapClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onClusterClick', ...)

```typescript
addListener(eventName: 'onClusterClick', listenerFunc: (data: ClusterClickCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| **`eventName`**    | <code>'onClusterClick'</code>                                                                    |
| **`listenerFunc`** | <code>(data: <a href="#clusterclickcallbackdata">ClusterClickCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onCameraMoveStarted', ...)

```typescript
addListener(eventName: 'onCameraMoveStarted', listenerFunc: (data: CameraMoveStartedCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                                       |
| ------------------ | ---------------------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onCameraMoveStarted'</code>                                                                         |
| **`listenerFunc`** | <code>(data: <a href="#cameramovestartedcallbackdata">CameraMoveStartedCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMarkerDragStart', ...)

```typescript
addListener(eventName: 'onMarkerDragStart', listenerFunc: (data: MarkerDragCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMarkerDragStart'</code>                                                             |
| **`listenerFunc`** | <code>(data: <a href="#markerdragcallbackdata">MarkerDragCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMarkerDrag', ...)

```typescript
addListener(eventName: 'onMarkerDrag', listenerFunc: (data: MarkerDragCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMarkerDrag'</code>                                                                  |
| **`listenerFunc`** | <code>(data: <a href="#markerdragcallbackdata">MarkerDragCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('onMarkerDragEnd', ...)

```typescript
addListener(eventName: 'onMarkerDragEnd', listenerFunc: (data: MarkerDragCallbackData) => void) => Promise<PluginListenerHandle>
```

| Param              | Type                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'onMarkerDragEnd'</code>                                                               |
| **`listenerFunc`** | <code>(data: <a href="#markerdragcallbackdata">MarkerDragCallbackData</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### Interfaces


#### PermissionStatus

Permission status for the plugin, keyed by alias. The only alias is
`location`, which gates the blue user-location dot ({@link
CapacitorAppleMapsPlugin.enableCurrentLocation}). The host app must also declare
`NSLocationWhenInUseUsageDescription` in its Info.plist for the prompt to appear.

| Prop           | Type                                                        |
| -------------- | ----------------------------------------------------------- |
| **`location`** | <code><a href="#permissionstate">PermissionState</a></code> |


#### AppleMapConfig

Initial map configuration. The `width`/`height`/`x`/`y`/`devicePixelRatio`
fields are populated by the {@link AppleMap} wrapper from the bound element's
bounding rectangle - callers do not set them.

| Prop                        | Type                                                      | Description                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`center`**                | <code><a href="#latlng">LatLng</a></code>                 |                                                                                                                                                                                                                                                                                                                                                                                                      |
| **`zoom`**                  | <code>number</code>                                       | Google-style zoom (0 = whole world). Converted to an MKCoordinateRegion span natively.                                                                                                                                                                                                                                                                                                               |
| **`minZoom`**               | <code>number</code>                                       | Hard zoom-out floor. Programmatic and gesture moves are clamped to this.                                                                                                                                                                                                                                                                                                                             |
| **`maxZoom`**               | <code>number</code>                                       |                                                                                                                                                                                                                                                                                                                                                                                                      |
| **`clustering`**            | <code>boolean</code>                                      | Start with clustering enabled, so markers added later cluster on their first render instead of briefly appearing as individual pins. Equivalent to calling {@link AppleMap.enableClustering} before any {@link AppleMap.addMarkers}, but without the flash. Defaults to `false`.                                                                                                                     |
| **`mapType`**               | <code><a href="#maptype">MapType</a></code>               | Base map imagery. Defaults to `standard`.                                                                                                                                                                                                                                                                                                                                                            |
| **`showInfoWindows`**       | <code>boolean</code>                                      | Show an info-window bubble (title + optional snippet) above a marker when it is tapped, closing when another marker or the map is tapped. Defaults to `false`, which preserves the tap-only behavior (`onMarkerClick` fires and no bubble appears). The bubble is drawn by the plugin rather than using MapKit's native callout, which does not render when the map is composited into the web view. |
| **`showsTraffic`**          | <code>boolean</code>                                      | Overlay live traffic conditions (`MKMapView.showsTraffic`). Defaults to `false`.                                                                                                                                                                                                                                                                                                                     |
| **`showsPointsOfInterest`** | <code>boolean</code>                                      | Show Apple's points of interest (shops, parks, …). Maps to a `MKPointOfInterestFilter` of `.includingAll` / `.excludingAll`. Defaults to `true` (MapKit's default).                                                                                                                                                                                                                                  |
| **`showsCompass`**          | <code>boolean</code>                                      | Show the compass when the map is rotated (`MKMapView.showsCompass`). Defaults to `true`.                                                                                                                                                                                                                                                                                                             |
| **`showsScale`**            | <code>boolean</code>                                      | Show the scale bar while zooming (`MKMapView.showsScale`). Defaults to `false`.                                                                                                                                                                                                                                                                                                                      |
| **`showsBuildings`**        | <code>boolean</code>                                      | Render extruded 3D buildings where MapKit has them (`MKMapView.showsBuildings`). Defaults to `true` (MapKit's default).                                                                                                                                                                                                                                                                              |
| **`colorScheme`**           | <code><a href="#mapcolorscheme">MapColorScheme</a></code> | Force a light/dark appearance regardless of the device setting. Defaults to `default` (follow system).                                                                                                                                                                                                                                                                                               |
| **`gestures`**              | <code><a href="#mapgestures">MapGestures</a></code>       | Which user gestures are enabled. Each defaults to `true`.                                                                                                                                                                                                                                                                                                                                            |
| **`padding`**               | <code><a href="#mappadding">MapPadding</a></code>         | Inset applied to the map's edges (controls + `fitBounds` framing).                                                                                                                                                                                                                                                                                                                                   |
| **`width`**                 | <code>number</code>                                       |                                                                                                                                                                                                                                                                                                                                                                                                      |
| **`height`**                | <code>number</code>                                       |                                                                                                                                                                                                                                                                                                                                                                                                      |
| **`x`**                     | <code>number</code>                                       |                                                                                                                                                                                                                                                                                                                                                                                                      |
| **`y`**                     | <code>number</code>                                       |                                                                                                                                                                                                                                                                                                                                                                                                      |
| **`devicePixelRatio`**      | <code>number</code>                                       |                                                                                                                                                                                                                                                                                                                                                                                                      |


#### LatLng

A geographic coordinate. Field names match `@capacitor/google-maps` so the
two plugins can sit behind one abstraction in the host app.

| Prop      | Type                |
| --------- | ------------------- |
| **`lat`** | <code>number</code> |
| **`lng`** | <code>number</code> |


#### MapGestures

Which user gestures the map responds to. Omitted fields are left unchanged.
All default to `true`.

| Prop         | Type                 | Description                              |
| ------------ | -------------------- | ---------------------------------------- |
| **`scroll`** | <code>boolean</code> | Pan/scroll the map.                      |
| **`zoom`**   | <code>boolean</code> | Pinch/double-tap to zoom.                |
| **`rotate`** | <code>boolean</code> | Two-finger rotate.                       |
| **`pitch`**  | <code>boolean</code> | Two-finger drag to tilt into 3D (pitch). |


#### MapPadding

Inset, in points, applied to the map's edges - it shifts MapKit's controls
(compass, scale, legal link) inward and pads the frame used by `fitBounds`.
Omitted sides default to `0`.

| Prop         | Type                |
| ------------ | ------------------- |
| **`top`**    | <code>number</code> |
| **`left`**   | <code>number</code> |
| **`right`**  | <code>number</code> |
| **`bottom`** | <code>number</code> |


#### CameraConfig

| Prop             | Type                                      | Description                                                                                                                                                                                                                      |
| ---------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`coordinate`** | <code><a href="#latlng">LatLng</a></code> |                                                                                                                                                                                                                                  |
| **`zoom`**       | <code>number</code>                       |                                                                                                                                                                                                                                  |
| **`bearing`**    | <code>number</code>                       | Camera heading (rotation) in degrees clockwise from true north (`0` = north up). Maps to `MKMapCamera.heading`. Left unchanged when omitted; requires the rotate gesture/`MKMapView` to keep it. Defaults to `0` on a fresh map. |
| **`angle`**      | <code>number</code>                       | Camera tilt in degrees from straight down (`0` = top-down; larger tilts toward the horizon for a 3D view). Maps to `MKMapCamera.pitch`. MapKit clamps the maximum tilt by zoom level. Left unchanged when omitted.               |
| **`animate`**    | <code>boolean</code>                      | Animate the camera move. Defaults to `false` to match the host app's expectations.                                                                                                                                               |


#### LatLngBounds

Visible-region bounds, mirroring the `@capacitor/google-maps` shape. A box
that crosses the antimeridian has `southwest.lng &gt; northeast.lng` (e.g. 178
to -179 is a 3-degree box), both when the plugin reports bounds and when you
pass them to `fitBounds` / `setCameraBoundary`.

| Prop            | Type                                      |
| --------------- | ----------------------------------------- |
| **`southwest`** | <code><a href="#latlng">LatLng</a></code> |
| **`center`**    | <code><a href="#latlng">LatLng</a></code> |
| **`northeast`** | <code><a href="#latlng">LatLng</a></code> |


#### CameraPosition

The map's current camera, returned by {@link CapacitorAppleMapsPlugin.getCameraPosition}.

| Prop            | Type                                                  | Description                                                                  |
| --------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------- |
| **`latitude`**  | <code>number</code>                                   |                                                                              |
| **`longitude`** | <code>number</code>                                   |                                                                              |
| **`zoom`**      | <code>number</code>                                   | Google-style zoom derived from the current region span.                      |
| **`bearing`**   | <code>number</code>                                   | Camera heading in degrees clockwise from true north (`MKMapCamera.heading`). |
| **`angle`**     | <code>number</code>                                   | Camera tilt in degrees from straight down (`MKMapCamera.pitch`).             |
| **`bounds`**    | <code><a href="#latlngbounds">LatLngBounds</a></code> |                                                                              |


#### Marker

| Prop             | Type                                                         | Description                                                                                                                                                                                                                                                                                                                                                              |
| ---------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **`coordinate`** | <code><a href="#latlng">LatLng</a></code>                    |                                                                                                                                                                                                                                                                                                                                                                          |
| **`title`**      | <code>string</code>                                          |                                                                                                                                                                                                                                                                                                                                                                          |
| **`snippet`**    | <code>string</code>                                          | Secondary line shown under `title` in the info-window bubble (see `showInfoWindows`).                                                                                                                                                                                                                                                                                    |
| **`iconUrl`**    | <code>string</code>                                          | Bundled asset filename (e.g. `marker-blue.png`, resolved from `public/`), an `https:` URL, or a `data:` URI. SVG is not supported by MapKit. Omit it to get MapKit's native default pin.                                                                                                                                                                                 |
| **`iconSize`**   | <code>{ width: number; height: number; }</code>              | Logical size in points.                                                                                                                                                                                                                                                                                                                                                  |
| **`iconAnchor`** | <code>{ x: number; y: number; }</code>                       | Where the icon is pinned to the coordinate, as fractions of the image measured from its top-left corner. `{ x: 0.5, y: 1 }` — the default — puts the bottom-centre on the coordinate, which suits a teardrop pin whose tip marks the spot; `{ x: 0.5, y: 0.5 }` centres the image on the coordinate, which suits a dot or a circular badge. Ignored without `iconUrl`.   |
| **`markerId`**   | <code>string</code>                                          | Caller-supplied stable id. When set it is used verbatim (and echoed back from {@link CapacitorAppleMapsPlugin.addMarkers} and on tap) instead of a generated one, so the host can map pins back to its own domain objects and target them with {@link CapacitorAppleMapsPlugin.updateMarkers}. Adding a marker whose id is already on the map replaces the existing pin. |
| **`draggable`**  | <code>boolean</code>                                         | Let the user drag this pin (press-and-hold, then move). Fires `onMarkerDragStart` / `onMarkerDrag` / `onMarkerDragEnd`. Defaults to `false`. A pin that is currently clustered can't be dragged until it separates into its own annotation.                                                                                                                              |
| **`opacity`**    | <code>number</code>                                          | <a href="#marker">Marker</a> opacity, `0` (transparent) to `1` (opaque). Applies to both custom icons and the default pin (`MKAnnotationView.alpha`). Defaults to `1`.                                                                                                                                                                                                   |
| **`tintColor`**  | <code>{ r: number; g: number; b: number; a: number; }</code> | Recolor the default MapKit pin (`MKMarkerAnnotationView.markerTintColor`), with each channel `0..255`. Ignored when `iconUrl` is set, since a custom image supplies its own colors.                                                                                                                                                                                      |
| **`zIndex`**     | <code>number</code>                                          | Draw order relative to other markers - a higher value draws on top. Maps to `MKAnnotationView.zPriority`. Defaults to `0`.                                                                                                                                                                                                                                               |


#### MarkerUpdate

A partial change to an existing marker, addressed by its `markerId`. Omitted
fields are left as-is; a moved marker animates to its new coordinate.

| Prop             | Type                                                                 | Description                                                                                             |
| ---------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| **`markerId`**   | <code>string</code>                                                  |                                                                                                         |
| **`coordinate`** | <code><a href="#latlng">LatLng</a></code>                            |                                                                                                         |
| **`title`**      | <code>string</code>                                                  |                                                                                                         |
| **`snippet`**    | <code>string</code>                                                  |                                                                                                         |
| **`iconUrl`**    | <code>string</code>                                                  |                                                                                                         |
| **`iconSize`**   | <code>{ width: number; height: number; }</code>                      |                                                                                                         |
| **`iconAnchor`** | <code>{ x: number; y: number; } \| null</code>                       | See {@link <a href="#marker">Marker.iconAnchor</a>}. Pass `null` to reset to the bottom-centre default. |
| **`draggable`**  | <code>boolean</code>                                                 | Enable or disable dragging for this marker.                                                             |
| **`opacity`**    | <code>number</code>                                                  | See {@link <a href="#marker">Marker.opacity</a>}.                                                       |
| **`tintColor`**  | <code>{ r: number; g: number; b: number; a: number; } \| null</code> | See {@link <a href="#marker">Marker.tintColor</a>}. Pass `null` to clear the tint.                      |
| **`zIndex`**     | <code>number</code>                                                  | See {@link <a href="#marker">Marker.zIndex</a>}.                                                        |


#### Polyline

Shared stroke/fill styling for overlays. Colors are `#RRGGBB` or `#RRGGBBAA` hex.

| Prop                  | Type                  | Description                                                                                                                                                |
| --------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`path`**            | <code>LatLng[]</code> |                                                                                                                                                            |
| **`strokeColor`**     | <code>string</code>   | Line color hex. Defaults to the system blue.                                                                                                               |
| **`strokeWeight`**    | <code>number</code>   | Line width in points. Defaults to `3`.                                                                                                                     |
| **`strokeOpacity`**   | <code>number</code>   | Line opacity `0..1`, applied on top of any alpha in `strokeColor`.                                                                                         |
| **`lineDashPattern`** | <code>number[]</code> | Dash pattern as alternating on/off segment lengths in points, e.g. `[8, 4]` for an 8-on/4-off dashed line. Omit (or pass an empty array) for a solid line. |
| **`geodesic`**        | <code>boolean</code>  | Follow the great-circle (shortest) path between points rather than a straight screen line - noticeable over long distances. Defaults to `false`.           |


#### Polygon

| Prop                  | Type                                | Description                                                                                                   |
| --------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **`paths`**           | <code>LatLng[] \| LatLng[][]</code> | Either a single ring of points, or an array of rings where the first is the exterior and the rest are holes.  |
| **`strokeColor`**     | <code>string</code>                 |                                                                                                               |
| **`strokeWeight`**    | <code>number</code>                 |                                                                                                               |
| **`strokeOpacity`**   | <code>number</code>                 |                                                                                                               |
| **`fillColor`**       | <code>string</code>                 | Fill color hex. Unfilled if omitted.                                                                          |
| **`fillOpacity`**     | <code>number</code>                 |                                                                                                               |
| **`lineDashPattern`** | <code>number[]</code>               | Dashed stroke pattern in points, e.g. `[8, 4]`. See {@link <a href="#polyline">Polyline.lineDashPattern</a>}. |


#### Circle

| Prop                  | Type                                      | Description                                                                                                   |
| --------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **`center`**          | <code><a href="#latlng">LatLng</a></code> |                                                                                                               |
| **`radius`**          | <code>number</code>                       | Radius in meters.                                                                                             |
| **`strokeColor`**     | <code>string</code>                       |                                                                                                               |
| **`strokeWeight`**    | <code>number</code>                       |                                                                                                               |
| **`strokeOpacity`**   | <code>number</code>                       |                                                                                                               |
| **`fillColor`**       | <code>string</code>                       |                                                                                                               |
| **`fillOpacity`**     | <code>number</code>                       |                                                                                                               |
| **`lineDashPattern`** | <code>number[]</code>                     | Dashed stroke pattern in points, e.g. `[8, 4]`. See {@link <a href="#polyline">Polyline.lineDashPattern</a>}. |


#### SearchCompletion

One type-ahead suggestion from `searchAutocomplete`.

| Prop           | Type                | Description                                        |
| -------------- | ------------------- | -------------------------------------------------- |
| **`id`**       | <code>string</code> | Opaque id to pass to `searchResolve`.              |
| **`title`**    | <code>string</code> | Primary line, e.g. a street address or place name. |
| **`subtitle`** | <code>string</code> | Secondary line, e.g. the city/region.              |


#### SearchRegion

Region to bias autocomplete toward - pass the map's current center so results
favour the area in view. Deltas default to 1° if omitted.

| Prop                 | Type                |
| -------------------- | ------------------- |
| **`latitude`**       | <code>number</code> |
| **`longitude`**      | <code>number</code> |
| **`latitudeDelta`**  | <code>number</code> |
| **`longitudeDelta`** | <code>number</code> |


#### SearchResult

One coordinate-bearing result from `searchPlaces`.

| Prop            | Type                | Description                                                             |
| --------------- | ------------------- | ----------------------------------------------------------------------- |
| **`id`**        | <code>string</code> | Opaque id to pass to `searchResolve` (or use the coordinates directly). |
| **`title`**     | <code>string</code> |                                                                         |
| **`subtitle`**  | <code>string</code> |                                                                         |
| **`latitude`**  | <code>number</code> |                                                                         |
| **`longitude`** | <code>number</code> |                                                                         |


#### SearchResolution

A suggestion resolved by `searchResolve`. Empty when nothing was found.

| Prop                 | Type                | Description                                                  |
| -------------------- | ------------------- | ------------------------------------------------------------ |
| **`lat`**            | <code>number</code> |                                                              |
| **`lng`**            | <code>number</code> |                                                              |
| **`title`**          | <code>string</code> |                                                              |
| **`latitudeDelta`**  | <code>number</code> | Degrees of latitude the place spans. Autocomplete ids only.  |
| **`longitudeDelta`** | <code>number</code> | Degrees of longitude the place spans. Autocomplete ids only. |


#### GeocodeResult

A place from `reverseGeocode` or `geocode`. Every field is optional: MapKit
fills in what it knows, and an empty object means nothing was found.

| Prop                     | Type                | Description                                                                                                                                          |
| ------------------------ | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`address`**            | <code>string</code> | The whole address on one line, formatted for the place's own country - e.g. `1 Main St, Boston MA 02110, United States`. The field to show a reader. |
| **`name`**               | <code>string</code> | MapKit's name for the place - a landmark, a street address, or a town.                                                                               |
| **`street`**             | <code>string</code> | House number and street, e.g. `1 Main St`.                                                                                                           |
| **`locality`**           | <code>string</code> | City or town.                                                                                                                                        |
| **`subLocality`**        | <code>string</code> | Neighbourhood or district.                                                                                                                           |
| **`administrativeArea`** | <code>string</code> | State, province or region - abbreviated where that is the convention.                                                                                |
| **`postalCode`**         | <code>string</code> |                                                                                                                                                      |
| **`country`**            | <code>string</code> |                                                                                                                                                      |
| **`countryCode`**        | <code>string</code> | ISO 3166-1 alpha-2, e.g. `US`.                                                                                                                       |
| **`latitude`**           | <code>number</code> |                                                                                                                                                      |
| **`longitude`**          | <code>number</code> |                                                                                                                                                      |


#### MapBounds

The rectangle the native map should occupy, in CSS pixels.

| Prop         | Type                |
| ------------ | ------------------- |
| **`x`**      | <code>number</code> |
| **`y`**      | <code>number</code> |
| **`width`**  | <code>number</code> |
| **`height`** | <code>number</code> |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


#### CameraIdleCallbackData

| Prop            | Type                                                  |
| --------------- | ----------------------------------------------------- |
| **`mapId`**     | <code>string</code>                                   |
| **`latitude`**  | <code>number</code>                                   |
| **`longitude`** | <code>number</code>                                   |
| **`zoom`**      | <code>number</code>                                   |
| **`bounds`**    | <code><a href="#latlngbounds">LatLngBounds</a></code> |


#### MarkerClickCallbackData

| Prop            | Type                |
| --------------- | ------------------- |
| **`mapId`**     | <code>string</code> |
| **`markerId`**  | <code>string</code> |
| **`latitude`**  | <code>number</code> |
| **`longitude`** | <code>number</code> |
| **`title`**     | <code>string</code> |


#### MapReadyCallbackData

| Prop        | Type                |
| ----------- | ------------------- |
| **`mapId`** | <code>string</code> |


#### MapClickCallbackData

| Prop            | Type                |
| --------------- | ------------------- |
| **`mapId`**     | <code>string</code> |
| **`latitude`**  | <code>number</code> |
| **`longitude`** | <code>number</code> |


#### PolygonClickCallbackData

A tap on a polygon overlay. `polygonId` is the id returned by `addPolygons`.

| Prop            | Type                |
| --------------- | ------------------- |
| **`mapId`**     | <code>string</code> |
| **`polygonId`** | <code>string</code> |
| **`latitude`**  | <code>number</code> |
| **`longitude`** | <code>number</code> |


#### PolylineClickCallbackData

A tap on a polyline overlay. `polylineId` is the id returned by `addPolylines`.

| Prop             | Type                |
| ---------------- | ------------------- |
| **`mapId`**      | <code>string</code> |
| **`polylineId`** | <code>string</code> |
| **`latitude`**   | <code>number</code> |
| **`longitude`**  | <code>number</code> |


#### CircleClickCallbackData

A tap on a circle overlay. `circleId` is the id returned by `addCircles`.

| Prop            | Type                |
| --------------- | ------------------- |
| **`mapId`**     | <code>string</code> |
| **`circleId`**  | <code>string</code> |
| **`latitude`**  | <code>number</code> |
| **`longitude`** | <code>number</code> |


#### ClusterClickCallbackData

A tap on a cluster bubble. Carries the members it groups.

| Prop            | Type                  | Description                               |
| --------------- | --------------------- | ----------------------------------------- |
| **`mapId`**     | <code>string</code>   |                                           |
| **`latitude`**  | <code>number</code>   |                                           |
| **`longitude`** | <code>number</code>   |                                           |
| **`count`**     | <code>number</code>   | Number of markers in the cluster.         |
| **`markerIds`** | <code>string[]</code> | The `markerId`s of the clustered markers. |


#### CameraMoveStartedCallbackData

Fired once when the camera begins moving, before `onCameraIdle`. `isGesture`
distinguishes a user pan/zoom/rotate from a programmatic move (a
{@link CapacitorAppleMapsPlugin.setCamera} / {@link CapacitorAppleMapsPlugin.fitBounds}
call). Mirrors `@capacitor/google-maps`'s `onCameraMoveStarted`.

| Prop            | Type                 | Description                                                        |
| --------------- | -------------------- | ------------------------------------------------------------------ |
| **`mapId`**     | <code>string</code>  |                                                                    |
| **`isGesture`** | <code>boolean</code> | `true` for a user gesture, `false` for a programmatic camera move. |


#### MarkerDragCallbackData

A drag on a `draggable` marker, carrying the marker's live coordinate.
`onMarkerDragStart` fires once when the drag begins, `onMarkerDrag` fires
continuously as it moves, and `onMarkerDragEnd` fires once on release.

| Prop            | Type                |
| --------------- | ------------------- |
| **`mapId`**     | <code>string</code> |
| **`markerId`**  | <code>string</code> |
| **`latitude`**  | <code>number</code> |
| **`longitude`** | <code>number</code> |


### Type Aliases


#### PermissionState

<code>'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'</code>


#### MapType

Base map imagery. Maps to `MKMapType`; the `*Flyover` variants render 3D
satellite imagery where Apple has it. Defaults to `standard`.

<code>'standard' | 'satellite' | 'hybrid' | 'satelliteFlyover' | 'hybridFlyover' | 'mutedStandard'</code>


#### MapColorScheme

Forces the map's light/dark appearance regardless of the device setting, via
`overrideUserInterfaceStyle`. `default` follows the system.

<code>'default' | 'light' | 'dark'</code>


#### UserTrackingMode

How the map follows the user's location. `none` disables tracking; `follow`
keeps the user centered; `followWithHeading` also rotates the map to match the
device heading. Maps to `MKUserTrackingMode`.

<code>'none' | 'follow' | 'followWithHeading'</code>


#### SearchResultType

A kind of suggestion `searchAutocomplete` may return, mirroring
`MKLocalSearchCompleter.ResultType`.

- `address` - towns, postal codes, regions and street addresses.
- `pointOfInterest` - businesses and landmarks.
- `query` - search-query suggestions ("coffee near me") rather than places.

<code>'address' | 'pointOfInterest' | 'query'</code>


#### MapLongClickCallbackData

A long-press on the map surface (not on a marker).

<code><a href="#mapclickcallbackdata">MapClickCallbackData</a></code>


#### MyLocationClickCallbackData

A tap on the blue user-location dot (`onMyLocationClick`).

<code><a href="#mapclickcallbackdata">MapClickCallbackData</a></code>

</docgen-api>

## Maintainers

| Maintainer    | GitHub                                    | Active |
| ------------- | ----------------------------------------- | ------ |
| pjaudiomv | [pjaudiomv](https://github.com/pjaudiomv) | yes    |

## Contributors

Thanks goes to these wonderful people
([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/pjaudiomv"><img src="https://avatars.githubusercontent.com/u/pjaudiomv?s=100" width="100px;" alt="pjaudiomv"/><br /><sub><b>pjaudiomv</b></sub></a><br /><a href="https://github.com/katamalabs/capacitor-plugin-apple-maps/commits?author=pjaudiomv" title="Code">💻</a> <a href="https://github.com/katamalabs/capacitor-plugin-apple-maps/commits?author=pjaudiomv" title="Documentation">📖</a> <a href="#maintenance-pjaudiomv" title="Maintenance">🚧</a> <a href="https://github.com/katamalabs/capacitor-plugin-apple-maps/commits?author=pjaudiomv" title="Tests">⚠️</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the
[all-contributors](https://github.com/all-contributors/all-contributors)
specification. Contributions of any kind are welcome!
