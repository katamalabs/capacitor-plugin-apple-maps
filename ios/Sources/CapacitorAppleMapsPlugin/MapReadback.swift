import Foundation
import MapKit
import UIKit
import Capacitor

// MARK: - Map: camera/bounds read-back + live marker styling
//
// Split out of CapacitorAppleMaps.swift to keep the core Map type within
// SwiftLint's length budget. These are still part of the same Map type: the
// payload readers behind getCameraPosition / getMapBounds, and the in-place
// style updates behind updateMarkers.

extension Map {

    /// Must be called on the main thread.
    func currentZoom() -> Double {
        let width = Double(mapView.bounds.width > 0 ? mapView.bounds.width : UIScreen.main.bounds.width)
        return longitudeDeltaToZoom(mapView.region.span.longitudeDelta, widthPoints: width)
    }

    /// Must be called on the main thread. Shape matches `LatLngBounds` in JS.
    func boundsPayload() -> PluginCallResultData {
        let region = mapView.region
        let corners = regionCorners(center: region.center, span: region.span)
        return [
            "center": ["lat": region.center.latitude, "lng": region.center.longitude],
            "southwest": ["lat": corners.southwest.latitude, "lng": corners.southwest.longitude],
            "northeast": ["lat": corners.northeast.latitude, "lng": corners.northeast.longitude]
        ]
    }

    /// Must be called on the main thread. Shape matches `CameraPosition` in JS.
    func cameraPayload() -> PluginCallResultData {
        let center = mapView.centerCoordinate
        let camera = mapView.camera
        return [
            "latitude": center.latitude,
            "longitude": center.longitude,
            "zoom": currentZoom(),
            "bearing": camera.heading,
            "angle": Double(camera.pitch),
            "bounds": boundsPayload()
        ]
    }

    /// Apply opacity / tint / z-order from an update payload to a marker and its
    /// live annotation view, so the change shows without re-adding the annotation
    /// (which would flash the pin). Only keys present in `obj` are touched. Must be
    /// called on the main thread.
    func applyLiveStyleUpdates(from obj: JSObject, to marker: AppleMapMarker) {
        if obj.keys.contains("opacity") {
            marker.opacity = CGFloat(obj["opacity"] as? Double ?? 1)
            mapView.view(for: marker)?.alpha = marker.opacity
        }
        if obj.keys.contains("zIndex") {
            marker.zIndex = obj["zIndex"] as? Double ?? 0
            mapView.view(for: marker)?.zPriority = MKAnnotationViewZPriority(rawValue: Float(marker.zIndex))
        }
        if obj.keys.contains("tintColor") {
            marker.tintColor = AppleMapMarker.parseTintColor(obj["tintColor"])
            if let markerView = mapView.view(for: marker) as? MKMarkerAnnotationView {
                markerView.markerTintColor = marker.tintColor
            }
        }
    }
}
