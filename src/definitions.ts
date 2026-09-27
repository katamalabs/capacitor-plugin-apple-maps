import type { PermissionState, PluginListenerHandle } from '@capacitor/core';

/**
 * Permission status for the plugin, keyed by alias. The only alias is
 * `location`, which gates the blue user-location dot ({@link
 * CapacitorAppleMapsPlugin.enableCurrentLocation}). The host app must also declare
 * `NSLocationWhenInUseUsageDescription` in its Info.plist for the prompt to appear.
 */
export interface PermissionStatus {
  location: PermissionState;
}

/**
 * A geographic coordinate. Field names match `@capacitor/google-maps` so the
 * two plugins can sit behind one abstraction in the host app.
 */
export interface LatLng {
  lat: number;
  lng: number;
}

/**
 * Initial map configuration. The `width`/`height`/`x`/`y`/`devicePixelRatio`
 * fields are populated by the {@link AppleMap} wrapper from the bound element's
 * bounding rectangle - callers do not set them.
 */
export interface AppleMapConfig {
  center: LatLng;
  /** Google-style zoom (0 = whole world). Converted to an MKCoordinateRegion span natively. */
  zoom: number;
  /** Hard zoom-out floor. Programmatic and gesture moves are clamped to this. */
  minZoom?: number;
  maxZoom?: number;
  /**
   * Start with clustering enabled, so markers added later cluster on their first
   * render instead of briefly appearing as individual pins. Equivalent to
   * calling {@link AppleMap.enableClustering} before any {@link AppleMap.addMarkers},
   * but without the flash. Defaults to `false`.
   */
  clustering?: boolean;
  /** Base map imagery. Defaults to `standard`. */
  mapType?: MapType;
  /**
   * Show an info-window bubble (title + optional snippet) above a marker when it
   * is tapped, closing when another marker or the map is tapped. Defaults to
   * `false`, which preserves the tap-only behavior (`onMarkerClick` fires and no
   * bubble appears). The bubble is drawn by the plugin rather than using MapKit's
   * native callout, which does not render when the map is composited into the web
   * view.
   */
  showInfoWindows?: boolean;
  /** Overlay live traffic conditions (`MKMapView.showsTraffic`). Defaults to `false`. */
  showsTraffic?: boolean;
  /**
   * Show Apple's points of interest (shops, parks, …). Maps to a
   * `MKPointOfInterestFilter` of `.includingAll` / `.excludingAll`. Defaults to
   * `true` (MapKit's default).
   */
  showsPointsOfInterest?: boolean;
  /** Show the compass when the map is rotated (`MKMapView.showsCompass`). Defaults to `true`. */
  showsCompass?: boolean;
  /** Show the scale bar while zooming (`MKMapView.showsScale`). Defaults to `false`. */
  showsScale?: boolean;
  /** Force a light/dark appearance regardless of the device setting. Defaults to `default` (follow system). */
  colorScheme?: MapColorScheme;
  /** Which user gestures are enabled. Each defaults to `true`. */
  gestures?: MapGestures;
  /** Inset applied to the map's edges (controls + `fitBounds` framing). */
  padding?: MapPadding;
  // --- Populated by the wrapper, not by callers. ---
  width?: number;
  height?: number;
  x?: number;
  y?: number;
  devicePixelRatio?: number;
}

/**
 * Which user gestures the map responds to. Omitted fields are left unchanged.
 * All default to `true`.
 */
export interface MapGestures {
  /** Pan/scroll the map. */
  scroll?: boolean;
  /** Pinch/double-tap to zoom. */
  zoom?: boolean;
  /** Two-finger rotate. */
  rotate?: boolean;
  /** Two-finger drag to tilt into 3D (pitch). */
  pitch?: boolean;
}

/**
 * Inset, in points, applied to the map's edges - it shifts MapKit's controls
 * (compass, scale, legal link) inward and pads the frame used by `fitBounds`.
 * Omitted sides default to `0`.
 */
export interface MapPadding {
  top?: number;
  left?: number;
  right?: number;
  bottom?: number;
}

export interface CameraConfig {
  coordinate?: LatLng;
  zoom?: number;
  /**
   * Camera heading (rotation) in degrees clockwise from true north (`0` = north
   * up). Maps to `MKMapCamera.heading`. Left unchanged when omitted; requires the
   * rotate gesture/`MKMapView` to keep it. Defaults to `0` on a fresh map.
   */
  bearing?: number;
  /**
   * Camera tilt in degrees from straight down (`0` = top-down; larger tilts
   * toward the horizon for a 3D view). Maps to `MKMapCamera.pitch`. MapKit clamps
   * the maximum tilt by zoom level. Left unchanged when omitted.
   */
  angle?: number;
  /** Animate the camera move. Defaults to `false` to match the host app's expectations. */
  animate?: boolean;
}

/** The map's current camera, returned by {@link CapacitorAppleMapsPlugin.getCameraPosition}. */
export interface CameraPosition {
  latitude: number;
  longitude: number;
  /** Google-style zoom derived from the current region span. */
  zoom: number;
  /** Camera heading in degrees clockwise from true north (`MKMapCamera.heading`). */
  bearing: number;
  /** Camera tilt in degrees from straight down (`MKMapCamera.pitch`). */
  angle: number;
  bounds: LatLngBounds;
}

/**
 * Base map imagery. Maps to `MKMapType`; the `*Flyover` variants render 3D
 * satellite imagery where Apple has it. Defaults to `standard`.
 */
export type MapType = 'standard' | 'satellite' | 'hybrid' | 'satelliteFlyover' | 'hybridFlyover' | 'mutedStandard';

/**
 * Forces the map's light/dark appearance regardless of the device setting, via
 * `overrideUserInterfaceStyle`. `default` follows the system.
 */
export type MapColorScheme = 'default' | 'light' | 'dark';

export interface Marker {
  coordinate: LatLng;
  title?: string;
  /** Secondary line shown under `title` in the info-window bubble (see `showInfoWindows`). */
  snippet?: string;
  /**
   * Bundled asset filename (e.g. `marker-blue.png`, resolved from `public/`),
   * an `https:` URL, or a `data:` URI. SVG is not supported by MapKit. Omit it
   * to get MapKit's native default pin.
   */
  iconUrl?: string;
  /** Logical size in points. */
  iconSize?: { width: number; height: number };
  /**
   * Where the icon is pinned to the coordinate, as fractions of the image
   * measured from its top-left corner. `{ x: 0.5, y: 1 }` — the default — puts
   * the bottom-centre on the coordinate, which suits a teardrop pin whose tip
   * marks the spot; `{ x: 0.5, y: 0.5 }` centres the image on the coordinate,
   * which suits a dot or a circular badge. Ignored without `iconUrl`.
   */
  iconAnchor?: { x: number; y: number };
  /**
   * Caller-supplied stable id. When set it is used verbatim (and echoed back
   * from {@link CapacitorAppleMapsPlugin.addMarkers} and on tap) instead of a
   * generated one, so the host can map pins back to its own domain objects and
   * target them with {@link CapacitorAppleMapsPlugin.updateMarkers}.
   */
  markerId?: string;
  /**
   * Let the user drag this pin (press-and-hold, then move). Fires
   * `onMarkerDragStart` / `onMarkerDrag` / `onMarkerDragEnd`. Defaults to
   * `false`. A pin that is currently clustered can't be dragged until it
   * separates into its own annotation.
   */
  draggable?: boolean;
  /**
   * Marker opacity, `0` (transparent) to `1` (opaque). Applies to both custom
   * icons and the default pin (`MKAnnotationView.alpha`). Defaults to `1`.
   */
  opacity?: number;
  /**
   * Recolor the default MapKit pin (`MKMarkerAnnotationView.markerTintColor`),
   * with each channel `0..255`. Ignored when `iconUrl` is set, since a custom
   * image supplies its own colors.
   */
  tintColor?: { r: number; g: number; b: number; a: number };
  /**
   * Draw order relative to other markers - a higher value draws on top. Maps to
   * `MKAnnotationView.zPriority`. Defaults to `0`.
   */
  zIndex?: number;
}

/**
 * A partial change to an existing marker, addressed by its `markerId`. Omitted
 * fields are left as-is; a moved marker animates to its new coordinate.
 */
export interface MarkerUpdate {
  markerId: string;
  coordinate?: LatLng;
  title?: string;
  snippet?: string;
  iconUrl?: string;
  iconSize?: { width: number; height: number };
  /** See {@link Marker.iconAnchor}. Pass `null` to reset to the bottom-centre default. */
  iconAnchor?: { x: number; y: number } | null;
  /** Enable or disable dragging for this marker. */
  draggable?: boolean;
  /** See {@link Marker.opacity}. */
  opacity?: number;
  /** See {@link Marker.tintColor}. Pass `null` to clear the tint. */
  tintColor?: { r: number; g: number; b: number; a: number } | null;
  /** See {@link Marker.zIndex}. */
  zIndex?: number;
}

/** Shared stroke/fill styling for overlays. Colors are `#RRGGBB` or `#RRGGBBAA` hex. */
export interface Polyline {
  path: LatLng[];
  /** Line color hex. Defaults to the system blue. */
  strokeColor?: string;
  /** Line width in points. Defaults to `3`. */
  strokeWeight?: number;
  /** Line opacity `0..1`, applied on top of any alpha in `strokeColor`. */
  strokeOpacity?: number;
}

export interface Polygon {
  /**
   * Either a single ring of points, or an array of rings where the first is the
   * exterior and the rest are holes.
   */
  paths: LatLng[] | LatLng[][];
  strokeColor?: string;
  strokeWeight?: number;
  strokeOpacity?: number;
  /** Fill color hex. Unfilled if omitted. */
  fillColor?: string;
  fillOpacity?: number;
}

export interface Circle {
  center: LatLng;
  /** Radius in meters. */
  radius: number;
  strokeColor?: string;
  strokeWeight?: number;
  strokeOpacity?: number;
  fillColor?: string;
  fillOpacity?: number;
}

/** Visible-region bounds, mirroring the `@capacitor/google-maps` shape. */
export interface LatLngBounds {
  southwest: LatLng;
  center: LatLng;
  northeast: LatLng;
}

/** The rectangle the native map should occupy, in CSS pixels. */
export interface MapBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CameraIdleCallbackData {
  mapId: string;
  latitude: number;
  longitude: number;
  zoom: number;
  bounds: LatLngBounds;
}

export interface MarkerClickCallbackData {
  mapId: string;
  markerId: string;
  latitude: number;
  longitude: number;
  title?: string;
}

/**
 * A drag on a `draggable` marker, carrying the marker's live coordinate.
 * `onMarkerDragStart` fires once when the drag begins, `onMarkerDrag` fires
 * continuously as it moves, and `onMarkerDragEnd` fires once on release.
 */
export interface MarkerDragCallbackData {
  mapId: string;
  markerId: string;
  latitude: number;
  longitude: number;
}

export interface MapReadyCallbackData {
  mapId: string;
}

export interface MapClickCallbackData {
  mapId: string;
  latitude: number;
  longitude: number;
}

/** A long-press on the map surface (not on a marker). */
export type MapLongClickCallbackData = MapClickCallbackData;

/** A tap on a polygon overlay. `polygonId` is the id returned by `addPolygons`. */
export interface PolygonClickCallbackData {
  mapId: string;
  polygonId: string;
  latitude: number;
  longitude: number;
}

/** A tap on a polyline overlay. `polylineId` is the id returned by `addPolylines`. */
export interface PolylineClickCallbackData {
  mapId: string;
  polylineId: string;
  latitude: number;
  longitude: number;
}

/** A tap on a circle overlay. `circleId` is the id returned by `addCircles`. */
export interface CircleClickCallbackData {
  mapId: string;
  circleId: string;
  latitude: number;
  longitude: number;
}

/** A tap on the blue user-location dot (`onMyLocationClick`). */
export type MyLocationClickCallbackData = MapClickCallbackData;

/**
 * Fired once when the camera begins moving, before `onCameraIdle`. `isGesture`
 * distinguishes a user pan/zoom/rotate from a programmatic move (a
 * {@link CapacitorAppleMapsPlugin.setCamera} / {@link CapacitorAppleMapsPlugin.fitBounds}
 * call). Mirrors `@capacitor/google-maps`'s `onCameraMoveStarted`.
 */
export interface CameraMoveStartedCallbackData {
  mapId: string;
  /** `true` for a user gesture, `false` for a programmatic camera move. */
  isGesture: boolean;
}

/** A tap on a cluster bubble. Carries the members it groups. */
export interface ClusterClickCallbackData {
  mapId: string;
  latitude: number;
  longitude: number;
  /** Number of markers in the cluster. */
  count: number;
  /** The `markerId`s of the clustered markers. */
  markerIds: string[];
}

/**
 * A kind of suggestion `searchAutocomplete` may return, mirroring
 * `MKLocalSearchCompleter.ResultType`.
 *
 * - `address` - towns, postal codes, regions and street addresses.
 * - `pointOfInterest` - businesses and landmarks.
 * - `query` - search-query suggestions ("coffee near me") rather than places.
 */
export type SearchResultType = 'address' | 'pointOfInterest' | 'query';

/** One type-ahead suggestion from `searchAutocomplete`. */
export interface SearchCompletion {
  /** Opaque id to pass to `searchResolve`. */
  id: string;
  /** Primary line, e.g. a street address or place name. */
  title: string;
  /** Secondary line, e.g. the city/region. */
  subtitle: string;
}

/** One coordinate-bearing result from `searchPlaces`. */
export interface SearchResult {
  /** Opaque id to pass to `searchResolve` (or use the coordinates directly). */
  id: string;
  title: string;
  subtitle: string;
  latitude: number;
  longitude: number;
}

/**
 * Region to bias autocomplete toward - pass the map's current center so results
 * favour the area in view. Deltas default to 1° if omitted.
 */
export interface SearchRegion {
  latitude: number;
  longitude: number;
  latitudeDelta?: number;
  longitudeDelta?: number;
}

/**
 * A place from `reverseGeocode` or `geocode`. Every field is optional: MapKit
 * fills in what it knows, and an empty object means nothing was found.
 */
export interface GeocodeResult {
  /**
   * The whole address on one line, formatted for the place's own country -
   * e.g. `1 Main St, Boston MA 02110, United States`. The field to show a reader.
   */
  address?: string;
  /** MapKit's name for the place - a landmark, a street address, or a town. */
  name?: string;
  /** House number and street, e.g. `1 Main St`. */
  street?: string;
  /** City or town. */
  locality?: string;
  /** Neighbourhood or district. */
  subLocality?: string;
  /** State, province or region - abbreviated where that is the convention. */
  administrativeArea?: string;
  postalCode?: string;
  country?: string;
  /** ISO 3166-1 alpha-2, e.g. `US`. */
  countryCode?: string;
  latitude?: number;
  longitude?: number;
}

/**
 * Low-level bridge to the native MapKit implementation. Most callers should use
 * the {@link AppleMap} wrapper instead of these methods directly.
 */
export interface CapacitorAppleMapsPlugin {
  /**
   * Current location-permission status without prompting. See
   * {@link enableCurrentLocation}.
   */
  checkPermissions(): Promise<PermissionStatus>;
  /**
   * Prompt for location permission if it has not been decided yet, then resolve
   * with the resulting status. If permission was already granted or denied this
   * resolves immediately without prompting (iOS only prompts once). Requires the
   * host app's `NSLocationWhenInUseUsageDescription` Info.plist key.
   */
  requestPermissions(): Promise<PermissionStatus>;
  create(options: { id: string; config: AppleMapConfig; element?: unknown; forceCreate?: boolean }): Promise<void>;
  destroy(options: { id: string }): Promise<void>;
  setCamera(options: { id: string; config: CameraConfig }): Promise<void>;
  getMapBounds(options: { id: string }): Promise<LatLngBounds>;
  /** Current camera as `{ latitude, longitude, zoom, bounds }`. */
  getCameraPosition(options: { id: string }): Promise<CameraPosition>;
  /**
   * Move the camera to fit `bounds`, insetting the visible rect by `padding`
   * points on every side (default `0`). Animates unless `animate` is `false`.
   */
  fitBounds(options: { id: string; bounds: LatLngBounds; padding?: number; animate?: boolean }): Promise<void>;
  addMarkers(options: { id: string; markers: Marker[] }): Promise<{ ids: string[] }>;
  /** Add a single marker, returning its id. Convenience over {@link addMarkers}. */
  addMarker(options: { id: string; marker: Marker }): Promise<{ id: string }>;
  /** Apply partial changes to existing markers, addressed by `markerId`. */
  updateMarkers(options: { id: string; markers: MarkerUpdate[] }): Promise<void>;
  removeMarkers(options: { id: string; markerIds: string[] }): Promise<void>;
  /** Remove a single marker by id. Convenience over {@link removeMarkers}. */
  removeMarker(options: { id: string; markerId: string }): Promise<void>;
  /**
   * Enable marker clustering. `minClusterSize` is a best-effort lower bound on how
   * many markers must be present before any clustering happens (MapKit has no
   * per-cluster minimum, so this gates clustering on the total marker count);
   * defaults to `2`.
   */
  enableClustering(options: { id: string; minClusterSize?: number }): Promise<void>;
  disableClustering(options: { id: string }): Promise<void>;

  addPolylines(options: { id: string; polylines: Polyline[] }): Promise<{ ids: string[] }>;
  addPolygons(options: { id: string; polygons: Polygon[] }): Promise<{ ids: string[] }>;
  addCircles(options: { id: string; circles: Circle[] }): Promise<{ ids: string[] }>;
  /** Remove overlays (polylines, polygons, or circles) by the ids their add call returned. */
  removeOverlays(options: { id: string; ids: string[] }): Promise<void>;

  /** Set the base map imagery. */
  setMapType(options: { id: string; mapType: MapType }): Promise<void>;
  /** Read the current base map imagery. */
  getMapType(options: { id: string }): Promise<{ mapType: MapType }>;
  /**
   * Show or hide the blue user-location dot. Call {@link requestPermissions}
   * first to obtain location permission, and declare the
   * `NSLocationWhenInUseUsageDescription` Info.plist key in the host app; without
   * granted permission MapKit shows nothing.
   */
  enableCurrentLocation(options: { id: string; enabled: boolean }): Promise<void>;

  /** Overlay or hide live traffic conditions (`MKMapView.showsTraffic`). */
  setTrafficEnabled(options: { id: string; enabled: boolean }): Promise<void>;
  /** Show or hide Apple's points of interest (a `.includingAll` / `.excludingAll` filter). */
  setPointsOfInterestEnabled(options: { id: string; enabled: boolean }): Promise<void>;
  /** Show or hide the compass (`MKMapView.showsCompass`). */
  setCompassEnabled(options: { id: string; enabled: boolean }): Promise<void>;
  /** Show or hide the scale bar (`MKMapView.showsScale`). */
  setScaleEnabled(options: { id: string; enabled: boolean }): Promise<void>;
  /** Force a light/dark appearance, or `default` to follow the device setting. */
  setColorScheme(options: { id: string; colorScheme: MapColorScheme }): Promise<void>;
  /** Enable or disable user gestures (only the fields you pass are changed). */
  setGestures(options: { id: string; gestures: MapGestures }): Promise<void>;
  /** Inset the map's edges (shifts controls inward and pads `fitBounds`). */
  setPadding(options: { id: string; padding: MapPadding }): Promise<void>;
  /**
   * Render the current map view to a PNG, returned as a `data:` URL - the visible
   * base map with the marker pins and overlays composited on top.
   */
  takeSnapshot(options: { id: string }): Promise<{ image: string }>;

  /**
   * Type-ahead place autocomplete via `MKLocalSearchCompleter`. Needs no API
   * key. Pass `region` to bias suggestions toward the area in view. Each result
   * carries an opaque `id`; pass it to {@link searchResolve} to get coordinates.
   *
   * Pass `resultTypes` to choose what kinds of suggestion come back - e.g.
   * `['address']` for a "where" field that wants towns, postal codes and street
   * addresses but not airports and coffee shops. Defaults to
   * `['address', 'pointOfInterest']`; an empty or unrecognised list falls back
   * to that default rather than returning nothing.
   */
  searchAutocomplete(options: {
    query: string;
    region?: SearchRegion;
    resultTypes?: SearchResultType[];
  }): Promise<{ results: SearchCompletion[] }>;
  /**
   * One-shot place search via `MKLocalSearch`. Unlike {@link searchAutocomplete}
   * the results carry coordinates up front. Pass `region` to scope/bias results,
   * `maxDistanceKm` to drop results farther than that from the region center
   * (e.g. a US ZIP that also exists abroad), and `limit` to cap the count.
   */
  searchPlaces(options: {
    query: string;
    region?: SearchRegion;
    maxDistanceKm?: number;
    limit?: number;
  }): Promise<{ results: SearchResult[] }>;
  /**
   * Resolve a suggestion `id` (from either search method) to coordinates.
   * Returns an empty object if the id is unknown or has no location.
   */
  searchResolve(options: { id: string }): Promise<{ lat?: number; lng?: number; title?: string }>;

  /**
   * Coordinates to an address via `CLGeocoder`. Needs no API key. Pass
   * `language` (a BCP 47 tag such as `es` or `fr-CA`) to localise the result;
   * it defaults to the device language.
   *
   * Fails soft: no match, an offline device and Apple's rate limit all resolve
   * an empty object rather than rejecting. Apple throttles geocoding per app, so
   * call this once per user action, not on every location update.
   */
  reverseGeocode(options: { latitude: number; longitude: number; language?: string }): Promise<GeocodeResult>;
  /**
   * A typed address to coordinates via `CLGeocoder`. Needs no API key. For
   * type-ahead or business names prefer {@link searchAutocomplete} /
   * {@link searchPlaces}; this is the fallback for free text. Fails soft like
   * {@link reverseGeocode}: check for `latitude` before using the result.
   */
  geocode(options: { address: string; language?: string }): Promise<GeocodeResult>;

  /** Keep the native frame in sync as the element resizes. */
  onResize(options: { id: string; mapBounds: MapBounds }): Promise<void>;
  /** Re-mount the native view after the element becomes visible again. */
  onDisplay(options: { id: string; mapBounds: MapBounds }): Promise<void>;
  /** Keep the native frame in sync as the page scrolls (no-op on iOS). */
  onScroll(options: { id: string; mapBounds: MapBounds }): Promise<void>;

  addListener(
    eventName: 'onCameraIdle',
    listenerFunc: (data: CameraIdleCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMarkerClick',
    listenerFunc: (data: MarkerClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onInfoWindowClick',
    listenerFunc: (data: MarkerClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMapReady',
    listenerFunc: (data: MapReadyCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMapClick',
    listenerFunc: (data: MapClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMapLongClick',
    listenerFunc: (data: MapLongClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onPolygonClick',
    listenerFunc: (data: PolygonClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onPolylineClick',
    listenerFunc: (data: PolylineClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onCircleClick',
    listenerFunc: (data: CircleClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMyLocationClick',
    listenerFunc: (data: MyLocationClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onClusterClick',
    listenerFunc: (data: ClusterClickCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onCameraMoveStarted',
    listenerFunc: (data: CameraMoveStartedCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMarkerDragStart',
    listenerFunc: (data: MarkerDragCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMarkerDrag',
    listenerFunc: (data: MarkerDragCallbackData) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'onMarkerDragEnd',
    listenerFunc: (data: MarkerDragCallbackData) => void,
  ): Promise<PluginListenerHandle>;
}
