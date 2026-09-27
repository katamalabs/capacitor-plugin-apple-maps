import Foundation
import MapKit
import Capacitor

// MARK: - Plugin: user-tracking / buildings / camera-boundary / selection bridge
//
// Split out of CapacitorAppleMapsPlugin.swift so the plugin type stays within
// SwiftLint's body-length budget. The per-map work lives on `Map` (MapControls.swift).

extension CapacitorAppleMapsPlugin {

    @objc func setUserTrackingMode(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setUserTrackingMode(call.getString("mode") ?? "none")
        call.resolve()
    }

    @objc func setUserTrackingButtonVisible(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setUserTrackingButton(call.getBool("visible", true))
        call.resolve()
    }

    @objc func setBuildingsEnabled(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setBuildings(call.getBool("enabled", true))
        call.resolve()
    }

    @objc func setCameraBoundary(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        // A bounds object restricts panning; omitting it (or null) clears the limit.
        if let boundsObj = call.getObject("bounds"),
           let swObj = boundsObj["southwest"] as? JSObject,
           let swLat = swObj["lat"] as? Double, let swLng = swObj["lng"] as? Double,
           let neObj = boundsObj["northeast"] as? JSObject,
           let neLat = neObj["lat"] as? Double, let neLng = neObj["lng"] as? Double {
            map.setCameraBoundary(
                southwest: CLLocationCoordinate2D(latitude: swLat, longitude: swLng),
                northeast: CLLocationCoordinate2D(latitude: neLat, longitude: neLng)
            )
        } else {
            map.setCameraBoundary(southwest: nil, northeast: nil)
        }
        call.resolve()
    }

    @objc func selectMarker(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let markerId = call.getString("markerId") else {
            call.reject("markerId is required", PluginError.invalidArgument)
            return
        }
        if map.selectMarker(markerId) {
            call.resolve()
        } else {
            call.reject("marker not found", PluginError.markerNotFound)
        }
    }

    @objc func deselectMarker(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.deselectMarker()
        call.resolve()
    }
}
