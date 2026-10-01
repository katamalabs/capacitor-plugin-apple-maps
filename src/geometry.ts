import type { LatLng, LatLngBounds } from './definitions';

/** Bring a longitude into [-180, 180]. Values already in range are left as-is (so 180 stays 180). */
function wrapLongitude(lng: number): number {
  if (lng >= -180 && lng <= 180) return lng;
  return ((((lng + 180) % 360) + 360) % 360) - 180;
}

/**
 * The narrowest west..east longitude range covering every value, going the short
 * way round the globe. Found by dropping the largest gap between neighbouring
 * longitudes, counting the gap that wraps from the last back to the first. When
 * the range crosses the antimeridian, `west` is greater than `east` (the
 * `@capacitor/google-maps` convention).
 */
function longitudeRange(lngs: number[]): { west: number; east: number } {
  const sorted = lngs.map(wrapLongitude).sort((a, b) => a - b);
  const last = sorted.length - 1;
  // The wrap-around gap wins ties, so ordinary data never comes back crossing.
  let largestGap = sorted[0] + 360 - sorted[last];
  let gapAfter = last;
  for (let i = 0; i < last; i++) {
    const gap = sorted[i + 1] - sorted[i];
    if (gap > largestGap) {
      largestGap = gap;
      gapAfter = i;
    }
  }
  if (gapAfter === last) return { west: sorted[0], east: sorted[last] };
  return { west: sorted[gapAfter + 1], east: sorted[gapAfter] };
}

/**
 * The smallest {@link LatLngBounds} enclosing every coordinate, with its center.
 * Points either side of the antimeridian (e.g. 179° and -179°) get a narrow box
 * across it, returned with `southwest.lng > northeast.lng`, rather than one
 * spanning the rest of the world. Throws on an empty list, since there is
 * nothing to frame. Pure (no native calls), so it can be unit-tested and reused
 * by {@link AppleMap.fitBounds}.
 */
export function boundsForCoordinates(coordinates: LatLng[]): LatLngBounds {
  if (coordinates.length === 0) {
    throw new Error('fitBounds: coordinates array is empty');
  }
  let south = coordinates[0].lat;
  let north = coordinates[0].lat;
  for (const { lat } of coordinates) {
    if (lat < south) south = lat;
    if (lat > north) north = lat;
  }
  const { west, east } = longitudeRange(coordinates.map((c) => c.lng));
  const width = east >= west ? east - west : east + 360 - west;
  return {
    southwest: { lat: south, lng: west },
    northeast: { lat: north, lng: east },
    center: { lat: (south + north) / 2, lng: wrapLongitude(west + width / 2) },
  };
}
