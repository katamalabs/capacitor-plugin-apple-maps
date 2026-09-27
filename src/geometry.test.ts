import { describe, expect, it } from 'vitest';

import { boundsForCoordinates } from './geometry';

describe('boundsForCoordinates', () => {
  it('encloses every coordinate and centers between the extremes', () => {
    const bounds = boundsForCoordinates([
      { lat: 10, lng: 20 },
      { lat: -5, lng: 40 },
      { lat: 3, lng: -10 },
    ]);
    expect(bounds.southwest).toEqual({ lat: -5, lng: -10 });
    expect(bounds.northeast).toEqual({ lat: 10, lng: 40 });
    expect(bounds.center).toEqual({ lat: (10 + -5) / 2, lng: (40 + -10) / 2 });
  });

  it('handles a single coordinate as a zero-size box on that point', () => {
    const point = { lat: 42.36, lng: -71.06 };
    const bounds = boundsForCoordinates([point]);
    expect(bounds.southwest).toEqual(point);
    expect(bounds.northeast).toEqual(point);
    expect(bounds.center).toEqual(point);
  });

  it('handles coordinates spanning the antimeridian and negative latitudes', () => {
    const bounds = boundsForCoordinates([
      { lat: -33.87, lng: 151.21 }, // Sydney
      { lat: 37.77, lng: -122.42 }, // San Francisco
    ]);
    // Simple min/max bounding box (does not wrap the antimeridian).
    expect(bounds.southwest).toEqual({ lat: -33.87, lng: -122.42 });
    expect(bounds.northeast).toEqual({ lat: 37.77, lng: 151.21 });
  });

  it('throws on an empty list', () => {
    expect(() => boundsForCoordinates([])).toThrow(/empty/);
  });
});
