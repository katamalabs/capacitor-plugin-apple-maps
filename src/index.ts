import type {
  GeocodeResult,
  PermissionStatus,
  SearchCompletion,
  SearchRegion,
  SearchResult,
  SearchResultType,
} from './definitions';
import { CapacitorAppleMaps } from './implementation';

export * from './definitions';
export { CapacitorAppleMaps } from './implementation';
export { AppleMap } from './map';
export type { CreateMapArgs } from './map';

/**
 * Current location-permission status without prompting. Location permission
 * gates the blue user-location dot ({@link AppleMap.enableCurrentLocation}).
 */
export function checkPermissions(): Promise<PermissionStatus> {
  return CapacitorAppleMaps.checkPermissions();
}

/**
 * Prompt for location permission if it has not been decided yet (iOS prompts
 * only once), then resolve with the resulting status. The host app must declare
 * `NSLocationWhenInUseUsageDescription` in its Info.plist.
 */
export function requestPermissions(): Promise<PermissionStatus> {
  return CapacitorAppleMaps.requestPermissions();
}

/**
 * Native place autocomplete (iOS, `MKLocalSearchCompleter`). No API key needed.
 * Returns suggestions keyed by an opaque id; resolve one with {@link searchResolve}.
 */
export function searchAutocomplete(options: {
  query: string;
  region?: SearchRegion;
  resultTypes?: SearchResultType[];
}): Promise<{ results: SearchCompletion[] }> {
  return CapacitorAppleMaps.searchAutocomplete(options);
}

/**
 * One-shot native place search (iOS, `MKLocalSearch`). Results carry
 * coordinates; supports region scoping, a distance filter, and a result limit.
 */
export function searchPlaces(options: {
  query: string;
  region?: SearchRegion;
  maxDistanceKm?: number;
  limit?: number;
}): Promise<{ results: SearchResult[] }> {
  return CapacitorAppleMaps.searchPlaces(options);
}

/** Resolve a suggestion id (from either search method) to coordinates (iOS). */
export function searchResolve(options: { id: string }): Promise<{ lat?: number; lng?: number; title?: string }> {
  return CapacitorAppleMaps.searchResolve(options);
}

/**
 * Coordinates to an address (iOS, `CLGeocoder`). No API key needed. Resolves an
 * empty object when nothing could be found - read `address` for a display line.
 */
export function reverseGeocode(options: {
  latitude: number;
  longitude: number;
  language?: string;
}): Promise<GeocodeResult> {
  return CapacitorAppleMaps.reverseGeocode(options);
}

/** A typed address to coordinates (iOS, `CLGeocoder`). Empty object when nothing matched. */
export function geocode(options: { address: string; language?: string }): Promise<GeocodeResult> {
  return CapacitorAppleMaps.geocode(options);
}
