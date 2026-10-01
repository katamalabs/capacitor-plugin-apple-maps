import Foundation
import MapKit

// MARK: - Bounds geometry
//
// Pure coordinate/map-rect math behind fitBounds, setCameraBoundary and the
// reported visible bounds. Split out of CapacitorAppleMaps.swift to keep it
// within SwiftLint's length budget; no MKMapView needed, so it's unit-tested
// directly (GeometryTests).

/// The `MKMapRect` spanning `southwest`..`northeast`. Latitude order doesn't
/// matter (latitude grows north but `MKMapPoint.y` grows south), but longitude
/// order does: following `@capacitor/google-maps`, a west edge east of the east
/// edge (`southwest.longitude > northeast.longitude`) means the box crosses the
/// antimeridian, so the rect runs eastward past the world's edge - which MapKit
/// supports - instead of spanning the rest of the globe. Pure so the framing math
/// can be unit-tested without an `MKMapView`.
func boundingMapRect(southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D) -> MKMapRect {
    let swPoint = MKMapPoint(southwest)
    let nePoint = MKMapPoint(northeast)
    var eastX = nePoint.x
    if southwest.longitude > northeast.longitude {
        eastX += MKMapSize.world.width
    }
    return MKMapRect(
        x: swPoint.x,
        y: min(swPoint.y, nePoint.y),
        width: eastX - swPoint.x,
        height: abs(swPoint.y - nePoint.y)
    )
}

/// The corner coordinates of a region, used to report the visible bounds to JS.
/// Longitudes are kept within -180...180: a view across the antimeridian comes
/// back with `southwest.longitude > northeast.longitude`, the same convention
/// `fitBounds` accepts. Pure function so it can be unit-tested without an
/// `MKMapView`.
func regionCorners(center: CLLocationCoordinate2D, span: MKCoordinateSpan)
-> (southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D) {
    // Fully zoomed out the view is the whole world; wrapping would collapse it.
    let west = span.longitudeDelta >= 360 ? -180 : wrapLongitude(center.longitude - span.longitudeDelta / 2)
    let east = span.longitudeDelta >= 360 ? 180 : wrapLongitude(center.longitude + span.longitudeDelta / 2)
    let southwest = CLLocationCoordinate2D(latitude: center.latitude - span.latitudeDelta / 2, longitude: west)
    let northeast = CLLocationCoordinate2D(latitude: center.latitude + span.latitudeDelta / 2, longitude: east)
    return (southwest, northeast)
}

/// A longitude brought into -180...180 (values already in range are unchanged).
func wrapLongitude(_ longitude: Double) -> Double {
    if longitude > 180 { return longitude - 360 }
    if longitude < -180 { return longitude + 360 }
    return longitude
}
