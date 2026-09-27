import type { LatLng, LatLngBounds } from './definitions';

/**
 * The smallest {@link LatLngBounds} enclosing every coordinate, with its center.
 * Throws on an empty list, since there is nothing to frame. Pure (no native
 * calls), so it can be unit-tested and reused by {@link AppleMap.fitBounds}.
 */
export function boundsForCoordinates(coordinates: LatLng[]): LatLngBounds {
  if (coordinates.length === 0) {
    throw new Error('fitBounds: coordinates array is empty');
  }
  let south = coordinates[0].lat;
  let north = coordinates[0].lat;
  let west = coordinates[0].lng;
  let east = coordinates[0].lng;
  for (const { lat, lng } of coordinates) {
    if (lat < south) south = lat;
    if (lat > north) north = lat;
    if (lng < west) west = lng;
    if (lng > east) east = lng;
  }
  return {
    southwest: { lat: south, lng: west },
    northeast: { lat: north, lng: east },
    center: { lat: (south + north) / 2, lng: (west + east) / 2 },
  };
}
