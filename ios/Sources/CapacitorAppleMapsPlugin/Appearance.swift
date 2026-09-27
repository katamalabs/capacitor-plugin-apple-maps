import Foundation
import MapKit
import UIKit
import Capacitor

// MARK: - Map appearance, location, gestures & padding (#8, #10)
//
// Split out of Overlays.swift to keep both files within SwiftLint's length
// budget. Map type + appearance toggles, the user-location dot, gesture toggles,
// and edge padding - the per-map methods plus their bridge entry points.

extension AppleMapConfig {
    /// Parses a `{ top, left, right, bottom }` object into edge insets, defaulting
    /// missing sides to 0. Pure, so it can be unit-tested.
    static func parsePadding(_ value: Any?) -> UIEdgeInsets {
        guard let obj = value as? JSObject else { return .zero }
        return UIEdgeInsets(
            top: CGFloat(obj["top"] as? Double ?? 0),
            left: CGFloat(obj["left"] as? Double ?? 0),
            bottom: CGFloat(obj["bottom"] as? Double ?? 0),
            right: CGFloat(obj["right"] as? Double ?? 0)
        )
    }
}

extension Map {

    func setMapType(_ type: String) {
        DispatchQueue.main.async { self.mapView.mapType = Map.mapType(from: type) }
    }

    /// The current base map imagery as a JS `MapType` string. Must be called on the
    /// main thread.
    func currentMapType() -> String {
        Map.mapTypeString(from: mapView.mapType)
    }

    func setCurrentLocation(_ enabled: Bool) {
        DispatchQueue.main.async { self.mapView.showsUserLocation = enabled }
    }

    /// Apply the create-time appearance toggles from a config in one pass. Must
    /// be called on the main thread (invoked from `render()`); the runtime setters
    /// below each target a single property.
    func applyAppearance(_ config: AppleMapConfig) {
        mapView.showsTraffic = config.showsTraffic
        mapView.pointOfInterestFilter = config.showsPointsOfInterest ? .includingAll : .excludingAll
        mapView.showsCompass = config.showsCompass
        mapView.showsScale = config.showsScale
        mapView.overrideUserInterfaceStyle = Map.userInterfaceStyle(from: config.colorScheme)
    }

    func setTraffic(_ enabled: Bool) {
        DispatchQueue.main.async { self.mapView.showsTraffic = enabled }
    }

    func setPointsOfInterest(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.mapView.pointOfInterestFilter = enabled ? .includingAll : .excludingAll
        }
    }

    func setCompass(_ enabled: Bool) {
        DispatchQueue.main.async { self.mapView.showsCompass = enabled }
    }

    func setScale(_ enabled: Bool) {
        DispatchQueue.main.async { self.mapView.showsScale = enabled }
    }

    func setColorScheme(_ scheme: String) {
        DispatchQueue.main.async {
            self.mapView.overrideUserInterfaceStyle = Map.userInterfaceStyle(from: scheme)
        }
    }

    /// Toggle user gestures; nil leaves that gesture unchanged.
    func setGestures(scroll: Bool?, zoom: Bool?, rotate: Bool?, pitch: Bool?) {
        DispatchQueue.main.async {
            if let scroll = scroll { self.mapView.isScrollEnabled = scroll }
            if let zoom = zoom { self.mapView.isZoomEnabled = zoom }
            if let rotate = rotate { self.mapView.isRotateEnabled = rotate }
            if let pitch = pitch { self.mapView.isPitchEnabled = pitch }
        }
    }

    func setPadding(_ insets: UIEdgeInsets) {
        DispatchQueue.main.async {
            self.mapView.layoutMargins = insets
            self.contentInsets = insets
        }
    }

    static func mapType(from string: String) -> MKMapType {
        switch string.lowercased() {
        case "satellite": return .satellite
        case "hybrid": return .hybrid
        case "satelliteflyover": return .satelliteFlyover
        case "hybridflyover": return .hybridFlyover
        case "mutedstandard": return .mutedStandard
        default: return .standard
        }
    }

    /// Inverse of `mapType(from:)` - the JS `MapType` string for an `MKMapType`.
    static func mapTypeString(from type: MKMapType) -> String {
        switch type {
        case .satellite: return "satellite"
        case .hybrid: return "hybrid"
        case .satelliteFlyover: return "satelliteFlyover"
        case .hybridFlyover: return "hybridFlyover"
        case .mutedStandard: return "mutedStandard"
        default: return "standard"
        }
    }

    /// Maps a `colorScheme` string to a `UIUserInterfaceStyle`; anything other
    /// than "light"/"dark" follows the system. Pure, so it can be unit-tested.
    static func userInterfaceStyle(from string: String) -> UIUserInterfaceStyle {
        switch string.lowercased() {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }
}

// MARK: - Plugin: appearance / gestures / padding bridge

extension CapacitorAppleMapsPlugin {

    @objc func setMapType(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let type = call.getString("mapType") else {
            call.reject("mapType is required", PluginError.invalidArgument)
            return
        }
        map.setMapType(type)
        call.resolve()
    }

    @objc func getMapType(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        runOnMainSync {
            call.resolve(["mapType": map.currentMapType()])
        }
    }

    @objc func enableCurrentLocation(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setCurrentLocation(call.getBool("enabled", true))
        call.resolve()
    }

    @objc func setTrafficEnabled(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setTraffic(call.getBool("enabled", true))
        call.resolve()
    }

    @objc func setPointsOfInterestEnabled(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setPointsOfInterest(call.getBool("enabled", true))
        call.resolve()
    }

    @objc func setCompassEnabled(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setCompass(call.getBool("enabled", true))
        call.resolve()
    }

    @objc func setScaleEnabled(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setScale(call.getBool("enabled", true))
        call.resolve()
    }

    @objc func setColorScheme(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setColorScheme(call.getString("colorScheme") ?? "default")
        call.resolve()
    }

    @objc func setGestures(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        let gestures = call.getObject("gestures") ?? [:]
        map.setGestures(
            scroll: gestures["scroll"] as? Bool,
            zoom: gestures["zoom"] as? Bool,
            rotate: gestures["rotate"] as? Bool,
            pitch: gestures["pitch"] as? Bool
        )
        call.resolve()
    }

    @objc func setPadding(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.setPadding(AppleMapConfig.parsePadding(call.getObject("padding")))
        call.resolve()
    }
}
