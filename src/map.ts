import { Capacitor } from '@capacitor/core';
import type { PluginListenerHandle } from '@capacitor/core';

import type {
  AppleMapConfig,
  CameraConfig,
  CameraIdleCallbackData,
  CameraMoveStartedCallbackData,
  CameraPosition,
  Circle,
  CircleClickCallbackData,
  ClusterClickCallbackData,
  LatLng,
  LatLngBounds,
  MapClickCallbackData,
  MapColorScheme,
  MapGestures,
  MapLongClickCallbackData,
  MapPadding,
  MapReadyCallbackData,
  MapType,
  Marker,
  MarkerClickCallbackData,
  MarkerDragCallbackData,
  MarkerUpdate,
  MyLocationClickCallbackData,
  Polygon,
  PolygonClickCallbackData,
  Polyline,
  PolylineClickCallbackData,
} from './definitions';
import { boundsForCoordinates } from './geometry';
import { CapacitorAppleMaps } from './implementation';

export interface CreateMapArgs {
  /** Unique id for this map instance. */
  id: string;
  /** The `<capacitor-apple-map>` (or any) element the native map is bound to. */
  element: HTMLElement;
  config: AppleMapConfig;
  /** Destroy and recreate if a map with this id already exists. */
  forceCreate?: boolean;
}

/**
 * Custom element the native map mounts into. On iOS it is given a scrollable
 * inner box so WKWebView materialises a child scroll view at the element's
 * dimensions - the native MapKit view is inserted into that subview. This is
 * the same compositing trick `@capacitor/google-maps` uses.
 */
class MapCustomElement extends HTMLElement {
  connectedCallback(): void {
    this.innerHTML = '';
    if (Capacitor.getPlatform() === 'ios') {
      this.style.overflow = 'scroll';
      (this.style as unknown as Record<string, string>)['-webkit-overflow-scrolling'] = 'touch';
      const overflowDiv = document.createElement('div');
      overflowDiv.style.height = '200%';
      this.appendChild(overflowDiv);
    }
  }
}

if (typeof customElements !== 'undefined' && !customElements.get('capacitor-apple-map')) {
  customElements.define('capacitor-apple-map', MapCustomElement);
}

/**
 * High-level handle to a native Apple Map. Create one with {@link AppleMap.create};
 * the API deliberately mirrors the subset of `@capacitor/google-maps`'s
 * `GoogleMap` that the host app relies on, so the two can share one abstraction.
 */
export class AppleMap {
  private id: string;
  private element: HTMLElement | null = null;
  private resizeObserver: ResizeObserver | null = null;
  private handleScrollEvent = (): void => this.updateMapBounds();

  private onCameraIdleListener?: PluginListenerHandle;
  private onCameraMoveStartedListener?: PluginListenerHandle;
  private onMarkerClickListener?: PluginListenerHandle;
  private onInfoWindowClickListener?: PluginListenerHandle;
  private onMapClickListener?: PluginListenerHandle;
  private onMapLongClickListener?: PluginListenerHandle;
  private onClusterClickListener?: PluginListenerHandle;
  private onPolygonClickListener?: PluginListenerHandle;
  private onPolylineClickListener?: PluginListenerHandle;
  private onCircleClickListener?: PluginListenerHandle;
  private onMyLocationClickListener?: PluginListenerHandle;
  private onBoundsChangedListener?: PluginListenerHandle;
  private onMarkerDragStartListener?: PluginListenerHandle;
  private onMarkerDragListener?: PluginListenerHandle;
  private onMarkerDragEndListener?: PluginListenerHandle;

  private constructor(id: string) {
    this.id = id;
  }

  static async create(options: CreateMapArgs): Promise<AppleMap> {
    const newMap = new AppleMap(options.id);

    if (!options.element) {
      throw new Error('container element is required');
    }

    newMap.element = options.element;
    newMap.element.dataset.internalId = options.id;

    // Wait until the element's box has settled — non-zero and unchanged across a
    // few frames — BEFORE measuring it. On a warm relaunch the element gets its
    // width first and its height (and final position) a few frames later; if we
    // measure too early the native map is placed against a stale frame and comes
    // up blank. Measuring only once the box is stable is what a caller otherwise
    // has to arrange with its own layout wait.
    await AppleMap.settleLayout(options.element);
    const bounds = await AppleMap.getElementBounds(options.element);
    options.config.width = bounds.width;
    options.config.height = bounds.height;
    options.config.x = bounds.x;
    options.config.y = bounds.y;
    options.config.devicePixelRatio = window.devicePixelRatio;

    if (Capacitor.isNativePlatform()) {
      // Keep the native frame synced as the element resizes or is re-shown.
      const getMapBounds = () => {
        const rect = newMap.element?.getBoundingClientRect() ?? ({} as DOMRect);
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
      };
      const onResize = () => CapacitorAppleMaps.onResize({ id: newMap.id, mapBounds: getMapBounds() });
      const onDisplay = () => CapacitorAppleMaps.onDisplay({ id: newMap.id, mapBounds: getMapBounds() });

      const lastState = { width: bounds.width, height: bounds.height, isHidden: false };
      newMap.resizeObserver = new ResizeObserver(() => {
        if (newMap.element == null) return;
        const rect = newMap.element.getBoundingClientRect();
        const isHidden = rect.width === 0 && rect.height === 0;
        if (!isHidden) {
          if (lastState.isHidden) {
            onDisplay();
          } else if (lastState.width !== rect.width || lastState.height !== rect.height) {
            onResize();
          }
        }
        lastState.width = rect.width;
        lastState.height = rect.height;
        lastState.isHidden = isHidden;
      });
      newMap.resizeObserver.observe(newMap.element);

      window.addEventListener('scroll', newMap.handleScrollEvent);
      window.addEventListener('resize', newMap.handleScrollEvent);
    }

    // Short settle so iOS WKWebView has materialised the element's child scroll
    // view (created off the `overflow: scroll` its connectedCallback set) before
    // the native map attaches to it.
    await new Promise<void>((resolve, reject) => {
      setTimeout(async () => {
        try {
          await CapacitorAppleMaps.create({ id: options.id, config: options.config, forceCreate: options.forceCreate });
          resolve();
        } catch (err) {
          reject(err);
        }
      }, 200);
    });

    return newMap;
  }

  /** Resolve on the next animation frame (or ~a frame later where none exists). */
  private static nextFrame(): Promise<void> {
    return new Promise((resolve) => {
      if (typeof requestAnimationFrame === 'function') {
        requestAnimationFrame(() => resolve());
      } else {
        setTimeout(resolve, 16);
      }
    });
  }

  /**
   * Wait until the element's bounding box is non-zero and unchanged across a few
   * consecutive frames, i.e. layout has settled. Bounded so a genuinely
   * zero-sized element resolves rather than hanging.
   */
  private static async settleLayout(element: HTMLElement, maxFrames = 60): Promise<void> {
    let prev = element.getBoundingClientRect();
    let stable = 0;
    for (let i = 0; i < maxFrames; i++) {
      await AppleMap.nextFrame();
      const rect = element.getBoundingClientRect();
      const unchanged =
        rect.width === prev.width && rect.height === prev.height && rect.x === prev.x && rect.y === prev.y;
      if (rect.width > 0 && rect.height > 0 && unchanged) {
        if (++stable >= 3) return;
      } else {
        stable = 0;
      }
      prev = rect;
    }
  }

  private static getElementBounds(element: HTMLElement): Promise<DOMRect> {
    // Wait for BOTH width and height, not just width: a flex/grid child is
    // often laid out with its full width a frame or two before it gets its
    // height, and creating the native map against a zero-height rect renders it
    // invisibly (a resolved-but-blank map). Checking only width was enough to
    // miss that and hand back a zero-height bounds.
    const isReady = (rect: DOMRect): boolean => rect.width !== 0 && rect.height !== 0;
    return new Promise((resolve) => {
      let bounds = element.getBoundingClientRect();
      if (isReady(bounds)) {
        resolve(bounds);
        return;
      }
      let retries = 0;
      const interval = setInterval(() => {
        bounds = element.getBoundingClientRect();
        if (isReady(bounds) || retries >= 30) {
          if (retries >= 30) console.warn('AppleMap: element size could not be determined');
          clearInterval(interval);
          resolve(bounds);
        }
        retries++;
      }, 100);
    });
  }

  private updateMapBounds(): void {
    if (!this.element) return;
    const rect = this.element.getBoundingClientRect();
    CapacitorAppleMaps.onScroll({
      id: this.id,
      mapBounds: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
    });
  }

  async setCamera(config: CameraConfig): Promise<void> {
    return CapacitorAppleMaps.setCamera({ id: this.id, config });
  }

  async getMapBounds(): Promise<LatLngBounds> {
    return CapacitorAppleMaps.getMapBounds({ id: this.id });
  }

  /** Read the current camera as `{ latitude, longitude, zoom, bounds }`. */
  async getCameraPosition(): Promise<CameraPosition> {
    return CapacitorAppleMaps.getCameraPosition({ id: this.id });
  }

  /**
   * Move the camera to fit either a {@link LatLngBounds} or a raw list of
   * `LatLng` coordinates, insetting by `padding` points on each side (default
   * `0`). Passing the coordinates directly saves computing the bounding box by
   * hand — the common path after {@link addMarkers} to frame every pin.
   */
  async fitBounds(target: LatLngBounds | LatLng[], padding?: number, animate = true): Promise<void> {
    const bounds = Array.isArray(target) ? boundsForCoordinates(target) : target;
    return CapacitorAppleMaps.fitBounds({ id: this.id, bounds, padding, animate });
  }

  async addMarkers(markers: Marker[]): Promise<string[]> {
    const res = await CapacitorAppleMaps.addMarkers({ id: this.id, markers });
    return res.ids;
  }

  /** Add a single marker, returning its id. Convenience over {@link addMarkers}. */
  async addMarker(marker: Marker): Promise<string> {
    const res = await CapacitorAppleMaps.addMarker({ id: this.id, marker });
    return res.id;
  }

  /** Apply partial changes to existing markers, addressed by `markerId`. */
  async updateMarkers(markers: MarkerUpdate[]): Promise<void> {
    return CapacitorAppleMaps.updateMarkers({ id: this.id, markers });
  }

  async removeMarkers(ids: string[]): Promise<void> {
    // Spread to a plain array: a reactive-framework proxy array (Svelte `$state`,
    // a Vue ref, etc.) does not survive Capacitor's bridge serialization as an
    // array, and the native side would see no ids.
    return CapacitorAppleMaps.removeMarkers({ id: this.id, markerIds: [...ids] });
  }

  /** Remove a single marker by id. Convenience over {@link removeMarkers}. */
  async removeMarker(id: string): Promise<void> {
    return CapacitorAppleMaps.removeMarker({ id: this.id, markerId: id });
  }

  /**
   * Enable marker clustering. `minClusterSize` is a best-effort lower bound on the
   * total marker count before clustering kicks in (MapKit has no per-cluster
   * minimum); defaults to `2`.
   */
  async enableClustering(minClusterSize?: number): Promise<void> {
    return CapacitorAppleMaps.enableClustering({ id: this.id, minClusterSize });
  }

  async disableClustering(): Promise<void> {
    return CapacitorAppleMaps.disableClustering({ id: this.id });
  }

  async addPolylines(polylines: Polyline[]): Promise<string[]> {
    const res = await CapacitorAppleMaps.addPolylines({ id: this.id, polylines });
    return res.ids;
  }

  async addPolygons(polygons: Polygon[]): Promise<string[]> {
    const res = await CapacitorAppleMaps.addPolygons({ id: this.id, polygons });
    return res.ids;
  }

  async addCircles(circles: Circle[]): Promise<string[]> {
    const res = await CapacitorAppleMaps.addCircles({ id: this.id, circles });
    return res.ids;
  }

  /** Remove overlays (polylines, polygons, or circles) by the ids their add call returned. */
  async removeOverlays(ids: string[]): Promise<void> {
    // Spread to a plain array — see the note in removeMarkers: a reactive proxy
    // array does not serialize across the bridge as an array.
    return CapacitorAppleMaps.removeOverlays({ id: this.id, ids: [...ids] });
  }

  async setMapType(mapType: MapType): Promise<void> {
    return CapacitorAppleMaps.setMapType({ id: this.id, mapType });
  }

  /** Read the current base map imagery. */
  async getMapType(): Promise<MapType> {
    const res = await CapacitorAppleMaps.getMapType({ id: this.id });
    return res.mapType;
  }

  /**
   * Show or hide the blue user-location dot. Requires the host app to declare
   * `NSLocationWhenInUseUsageDescription` and to have obtained location
   * permission; MapKit shows nothing otherwise.
   */
  async enableCurrentLocation(enabled: boolean): Promise<void> {
    return CapacitorAppleMaps.enableCurrentLocation({ id: this.id, enabled });
  }

  /** Overlay or hide live traffic conditions. */
  async setTrafficEnabled(enabled: boolean): Promise<void> {
    return CapacitorAppleMaps.setTrafficEnabled({ id: this.id, enabled });
  }

  /** Show or hide Apple's points of interest. */
  async setPointsOfInterestEnabled(enabled: boolean): Promise<void> {
    return CapacitorAppleMaps.setPointsOfInterestEnabled({ id: this.id, enabled });
  }

  /** Show or hide the compass (visible when the map is rotated). */
  async setCompassEnabled(enabled: boolean): Promise<void> {
    return CapacitorAppleMaps.setCompassEnabled({ id: this.id, enabled });
  }

  /** Show or hide the scale bar (visible while zooming). */
  async setScaleEnabled(enabled: boolean): Promise<void> {
    return CapacitorAppleMaps.setScaleEnabled({ id: this.id, enabled });
  }

  /** Force a light/dark appearance, or `default` to follow the device setting. */
  async setColorScheme(colorScheme: MapColorScheme): Promise<void> {
    return CapacitorAppleMaps.setColorScheme({ id: this.id, colorScheme });
  }

  /** Enable or disable user gestures (only the fields you pass are changed). */
  async setGestures(gestures: MapGestures): Promise<void> {
    return CapacitorAppleMaps.setGestures({ id: this.id, gestures });
  }

  /** Inset the map's edges (shifts controls inward and pads `fitBounds`). */
  async setPadding(padding: MapPadding): Promise<void> {
    return CapacitorAppleMaps.setPadding({ id: this.id, padding });
  }

  /**
   * Render the current map view to a PNG `data:` URL - the visible base map with
   * the marker pins and overlays composited on top.
   */
  async takeSnapshot(): Promise<string> {
    const res = await CapacitorAppleMaps.takeSnapshot({ id: this.id });
    return res.image;
  }

  async setOnCameraIdleListener(callback?: (data: CameraIdleCallbackData) => void): Promise<void> {
    if (this.onCameraIdleListener) {
      await this.onCameraIdleListener.remove();
      this.onCameraIdleListener = undefined;
    }
    if (callback) {
      this.onCameraIdleListener = await CapacitorAppleMaps.addListener('onCameraIdle', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnCameraMoveStartedListener(callback?: (data: CameraMoveStartedCallbackData) => void): Promise<void> {
    if (this.onCameraMoveStartedListener) {
      await this.onCameraMoveStartedListener.remove();
      this.onCameraMoveStartedListener = undefined;
    }
    if (callback) {
      this.onCameraMoveStartedListener = await CapacitorAppleMaps.addListener('onCameraMoveStarted', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMarkerClickListener(callback?: (data: MarkerClickCallbackData) => void): Promise<void> {
    if (this.onMarkerClickListener) {
      await this.onMarkerClickListener.remove();
      this.onMarkerClickListener = undefined;
    }
    if (callback) {
      this.onMarkerClickListener = await CapacitorAppleMaps.addListener('onMarkerClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  /** Fires when the info-window bubble (see `showInfoWindows`) is tapped. */
  async setOnInfoWindowClickListener(callback?: (data: MarkerClickCallbackData) => void): Promise<void> {
    if (this.onInfoWindowClickListener) {
      await this.onInfoWindowClickListener.remove();
      this.onInfoWindowClickListener = undefined;
    }
    if (callback) {
      this.onInfoWindowClickListener = await CapacitorAppleMaps.addListener('onInfoWindowClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMapClickListener(callback?: (data: MapClickCallbackData) => void): Promise<void> {
    if (this.onMapClickListener) {
      await this.onMapClickListener.remove();
      this.onMapClickListener = undefined;
    }
    if (callback) {
      this.onMapClickListener = await CapacitorAppleMaps.addListener('onMapClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMapLongClickListener(callback?: (data: MapLongClickCallbackData) => void): Promise<void> {
    if (this.onMapLongClickListener) {
      await this.onMapLongClickListener.remove();
      this.onMapLongClickListener = undefined;
    }
    if (callback) {
      this.onMapLongClickListener = await CapacitorAppleMaps.addListener('onMapLongClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnClusterClickListener(callback?: (data: ClusterClickCallbackData) => void): Promise<void> {
    if (this.onClusterClickListener) {
      await this.onClusterClickListener.remove();
      this.onClusterClickListener = undefined;
    }
    if (callback) {
      this.onClusterClickListener = await CapacitorAppleMaps.addListener('onClusterClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  /** Fires when a polygon overlay is tapped. */
  async setOnPolygonClickListener(callback?: (data: PolygonClickCallbackData) => void): Promise<void> {
    if (this.onPolygonClickListener) {
      await this.onPolygonClickListener.remove();
      this.onPolygonClickListener = undefined;
    }
    if (callback) {
      this.onPolygonClickListener = await CapacitorAppleMaps.addListener('onPolygonClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  /** Fires when a polyline overlay is tapped. */
  async setOnPolylineClickListener(callback?: (data: PolylineClickCallbackData) => void): Promise<void> {
    if (this.onPolylineClickListener) {
      await this.onPolylineClickListener.remove();
      this.onPolylineClickListener = undefined;
    }
    if (callback) {
      this.onPolylineClickListener = await CapacitorAppleMaps.addListener('onPolylineClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  /** Fires when a circle overlay is tapped. */
  async setOnCircleClickListener(callback?: (data: CircleClickCallbackData) => void): Promise<void> {
    if (this.onCircleClickListener) {
      await this.onCircleClickListener.remove();
      this.onCircleClickListener = undefined;
    }
    if (callback) {
      this.onCircleClickListener = await CapacitorAppleMaps.addListener('onCircleClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  /** Fires when the blue user-location dot is tapped (see `enableCurrentLocation`). */
  async setOnMyLocationClickListener(callback?: (data: MyLocationClickCallbackData) => void): Promise<void> {
    if (this.onMyLocationClickListener) {
      await this.onMyLocationClickListener.remove();
      this.onMyLocationClickListener = undefined;
    }
    if (callback) {
      this.onMyLocationClickListener = await CapacitorAppleMaps.addListener('onMyLocationClick', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  /**
   * Fires when the camera settles after a move. Alias of
   * {@link setOnCameraIdleListener}, provided for `@capacitor/google-maps` parity.
   */
  async setOnBoundsChangedListener(callback?: (data: CameraIdleCallbackData) => void): Promise<void> {
    if (this.onBoundsChangedListener) {
      await this.onBoundsChangedListener.remove();
      this.onBoundsChangedListener = undefined;
    }
    if (callback) {
      this.onBoundsChangedListener = await CapacitorAppleMaps.addListener('onCameraIdle', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMarkerDragStartListener(callback?: (data: MarkerDragCallbackData) => void): Promise<void> {
    if (this.onMarkerDragStartListener) {
      await this.onMarkerDragStartListener.remove();
      this.onMarkerDragStartListener = undefined;
    }
    if (callback) {
      this.onMarkerDragStartListener = await CapacitorAppleMaps.addListener('onMarkerDragStart', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMarkerDragListener(callback?: (data: MarkerDragCallbackData) => void): Promise<void> {
    if (this.onMarkerDragListener) {
      await this.onMarkerDragListener.remove();
      this.onMarkerDragListener = undefined;
    }
    if (callback) {
      this.onMarkerDragListener = await CapacitorAppleMaps.addListener('onMarkerDrag', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMarkerDragEndListener(callback?: (data: MarkerDragCallbackData) => void): Promise<void> {
    if (this.onMarkerDragEndListener) {
      await this.onMarkerDragEndListener.remove();
      this.onMarkerDragEndListener = undefined;
    }
    if (callback) {
      this.onMarkerDragEndListener = await CapacitorAppleMaps.addListener('onMarkerDragEnd', (data) => {
        if (data.mapId === this.id) callback(data);
      });
    }
  }

  async setOnMapReadyListener(callback?: (data: MapReadyCallbackData) => void): Promise<void> {
    if (callback) {
      const handle = await CapacitorAppleMaps.addListener('onMapReady', (data) => {
        if (data.mapId === this.id) callback(data);
      });
      // One-shot; caller does not need the handle.
      void handle;
    }
  }

  async destroy(): Promise<void> {
    if (Capacitor.isNativePlatform()) {
      window.removeEventListener('scroll', this.handleScrollEvent);
      window.removeEventListener('resize', this.handleScrollEvent);
    }
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    await this.onCameraIdleListener?.remove();
    await this.onCameraMoveStartedListener?.remove();
    await this.onMarkerClickListener?.remove();
    await this.onMapClickListener?.remove();
    await this.onMapLongClickListener?.remove();
    await this.onClusterClickListener?.remove();
    await this.onPolygonClickListener?.remove();
    await this.onPolylineClickListener?.remove();
    await this.onCircleClickListener?.remove();
    await this.onMyLocationClickListener?.remove();
    await this.onBoundsChangedListener?.remove();
    await this.onMarkerDragStartListener?.remove();
    await this.onMarkerDragListener?.remove();
    await this.onMarkerDragEndListener?.remove();
    await this.onInfoWindowClickListener?.remove();
    this.onCameraIdleListener = undefined;
    this.onCameraMoveStartedListener = undefined;
    this.onMarkerClickListener = undefined;
    this.onMapClickListener = undefined;
    this.onMapLongClickListener = undefined;
    this.onClusterClickListener = undefined;
    this.onPolygonClickListener = undefined;
    this.onPolylineClickListener = undefined;
    this.onCircleClickListener = undefined;
    this.onMyLocationClickListener = undefined;
    this.onBoundsChangedListener = undefined;
    this.onMarkerDragStartListener = undefined;
    this.onMarkerDragListener = undefined;
    this.onMarkerDragEndListener = undefined;
    this.onInfoWindowClickListener = undefined;
    return CapacitorAppleMaps.destroy({ id: this.id });
  }
}
