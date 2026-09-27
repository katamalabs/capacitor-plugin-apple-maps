import Foundation
import MapKit
import Capacitor

// MARK: - Plugin: marker + clustering bridge
//
// Split out of CapacitorAppleMapsPlugin.swift so the plugin type stays within
// SwiftLint's body-length budget. These are still bridge methods on the same
// plugin type; the per-map work lives on `Map` (CapacitorAppleMaps.swift).

extension CapacitorAppleMapsPlugin {

    @objc func addMarkers(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let markerObjs = call.getArray("markers") as? [JSObject] else {
            call.reject("markers array is required", PluginError.invalidArgument)
            return
        }
        let ids = map.addMarkers(markerObjs)
        call.resolve(["ids": ids])
    }

    @objc func addMarker(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let markerObj = call.getObject("marker") else {
            call.reject("marker is required", PluginError.invalidArgument)
            return
        }
        guard let markerId = map.addMarkers([markerObj]).first else {
            call.reject("marker is missing or malformed", PluginError.invalidArgument)
            return
        }
        call.resolve(["id": markerId])
    }

    @objc func updateMarkers(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let markerObjs = call.getArray("markers") as? [JSObject] else {
            call.reject("markers array is required", PluginError.invalidArgument)
            return
        }
        map.updateMarkers(markerObjs)
        call.resolve()
    }

    @objc func removeMarkers(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let ids = call.getArray("markerIds") as? [String] else {
            call.reject("markerIds array is required", PluginError.invalidArgument)
            return
        }
        map.removeMarkers(ids)
        call.resolve()
    }

    @objc func removeMarker(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let markerId = call.getString("markerId") else {
            call.reject("markerId is required", PluginError.invalidArgument)
            return
        }
        map.removeMarkers([markerId])
        call.resolve()
    }

    @objc func enableClustering(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.enableClustering()
        call.resolve()
    }

    @objc func disableClustering(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.disableClustering()
        call.resolve()
    }
}
