import { WebPlugin } from '@capacitor/core';

import type { CapacitorAppleMapsPlugin, LatLngBounds, PermissionStatus } from './definitions';

/**
 * Web fallback. Apple Maps is a native MapKit feature with no web surface here,
 * so every method rejects with `unavailable`. The host app should route web
 * (and Android) to another map provider rather than calling this plugin.
 */
export class CapacitorAppleMapsWeb extends WebPlugin implements CapacitorAppleMapsPlugin {
  private notAvailable(): never {
    throw this.unavailable('Apple Maps is only available on iOS.');
  }

  async checkPermissions(): Promise<PermissionStatus> {
    this.notAvailable();
  }

  async requestPermissions(): Promise<PermissionStatus> {
    this.notAvailable();
  }

  async create(): Promise<void> {
    this.notAvailable();
  }

  async destroy(): Promise<void> {
    this.notAvailable();
  }

  async setCamera(): Promise<void> {
    this.notAvailable();
  }

  async getMapBounds(): Promise<LatLngBounds> {
    this.notAvailable();
  }

  async getCameraPosition(): Promise<never> {
    this.notAvailable();
  }

  async fitBounds(): Promise<void> {
    this.notAvailable();
  }

  async addMarkers(): Promise<{ ids: string[] }> {
    this.notAvailable();
  }

  async addMarker(): Promise<{ id: string }> {
    this.notAvailable();
  }

  async updateMarkers(): Promise<void> {
    this.notAvailable();
  }

  async removeMarkers(): Promise<void> {
    this.notAvailable();
  }

  async removeMarker(): Promise<void> {
    this.notAvailable();
  }

  async enableClustering(): Promise<void> {
    this.notAvailable();
  }

  async disableClustering(): Promise<void> {
    this.notAvailable();
  }

  async addPolylines(): Promise<{ ids: string[] }> {
    this.notAvailable();
  }

  async addPolygons(): Promise<{ ids: string[] }> {
    this.notAvailable();
  }

  async addCircles(): Promise<{ ids: string[] }> {
    this.notAvailable();
  }

  async removeOverlays(): Promise<void> {
    this.notAvailable();
  }

  async setMapType(): Promise<void> {
    this.notAvailable();
  }

  async getMapType(): Promise<never> {
    this.notAvailable();
  }

  async setUserTrackingMode(): Promise<void> {
    this.notAvailable();
  }

  async setUserTrackingButtonVisible(): Promise<void> {
    this.notAvailable();
  }

  async setBuildingsEnabled(): Promise<void> {
    this.notAvailable();
  }

  async setCameraBoundary(): Promise<void> {
    this.notAvailable();
  }

  async selectMarker(): Promise<void> {
    this.notAvailable();
  }

  async deselectMarker(): Promise<void> {
    this.notAvailable();
  }

  async enableCurrentLocation(): Promise<void> {
    this.notAvailable();
  }

  async setTrafficEnabled(): Promise<void> {
    this.notAvailable();
  }

  async setPointsOfInterestEnabled(): Promise<void> {
    this.notAvailable();
  }

  async setCompassEnabled(): Promise<void> {
    this.notAvailable();
  }

  async setScaleEnabled(): Promise<void> {
    this.notAvailable();
  }

  async setColorScheme(): Promise<void> {
    this.notAvailable();
  }

  async setGestures(): Promise<void> {
    this.notAvailable();
  }

  async setPadding(): Promise<void> {
    this.notAvailable();
  }

  async takeSnapshot(): Promise<{ image: string }> {
    this.notAvailable();
  }

  async searchAutocomplete(): Promise<{ results: never[] }> {
    this.notAvailable();
  }

  async searchPlaces(): Promise<{ results: never[] }> {
    this.notAvailable();
  }

  async searchResolve(): Promise<{ lat?: number; lng?: number; title?: string }> {
    this.notAvailable();
  }

  async reverseGeocode(): Promise<never> {
    this.notAvailable();
  }

  async geocode(): Promise<never> {
    this.notAvailable();
  }

  async onResize(): Promise<void> {
    this.notAvailable();
  }

  async onDisplay(): Promise<void> {
    this.notAvailable();
  }

  async onScroll(): Promise<void> {
    this.notAvailable();
  }
}
