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

  it('frames points either side of the antimeridian with a narrow box across it', () => {
    const bounds = boundsForCoordinates([
      { lat: -17.8, lng: 178.4 }, // Fiji, west of the line
      { lat: -16.5, lng: -179.9 }, // Fiji, east of the line
      { lat: -18.1, lng: 179.2 },
    ]);
    // Crossing is signalled by southwest.lng > northeast.lng (Google's convention).
    expect(bounds.southwest).toEqual({ lat: -18.1, lng: 178.4 });
    expect(bounds.northeast).toEqual({ lat: -16.5, lng: -179.9 });
    expect(bounds.center.lat).toBeCloseTo(-17.3);
    expect(bounds.center.lng).toBeCloseTo(179.25);
  });

  it('puts the center on the far side of the antimeridian when that is the middle', () => {
    const bounds = boundsForCoordinates([
      { lat: 0, lng: 179 },
      { lat: 0, lng: -177 },
    ]);
    expect(bounds.center.lng).toBeCloseTo(-179);
  });

  it('takes the shorter way round between distant points', () => {
    const bounds = boundsForCoordinates([
      { lat: -33.87, lng: 151.21 }, // Sydney
      { lat: 37.77, lng: -122.42 }, // San Francisco
    ]);
    // Across the Pacific is ~86 degrees; the min/max box would be ~274.
    expect(bounds.southwest).toEqual({ lat: -33.87, lng: 151.21 });
    expect(bounds.northeast).toEqual({ lat: 37.77, lng: -122.42 });
  });

  it('keeps the ordinary box when both ways round are equally wide', () => {
    const bounds = boundsForCoordinates([
      { lat: 0, lng: -90 },
      { lat: 0, lng: 90 },
    ]);
    expect(bounds.southwest.lng).toBe(-90);
    expect(bounds.northeast.lng).toBe(90);
    expect(bounds.center.lng).toBe(0);
  });

  it('accepts longitudes outside -180..180', () => {
    const bounds = boundsForCoordinates([
      { lat: 0, lng: 181 },
      { lat: 0, lng: 179 },
    ]);
    expect(bounds.southwest.lng).toBe(179);
    expect(bounds.northeast.lng).toBe(-179);
  });

  it('throws on an empty list', () => {
    expect(() => boundsForCoordinates([])).toThrow(/empty/);
  });
});
