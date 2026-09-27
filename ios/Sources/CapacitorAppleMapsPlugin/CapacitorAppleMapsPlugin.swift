import Foundation
import Capacitor
import MapKit
import UIKit

/**
 * Bridges the JS API to native MapKit and relays map events back to JS.
 * See CapacitorAppleMaps.swift for the per-map implementation.
 */
@objc(CapacitorAppleMapsPlugin)
public class CapacitorAppleMapsPlugin: CAPPlugin, CAPBridgedPlugin, MKMapViewDelegate {
    public let identifier = "CapacitorAppleMapsPlugin"
    public let jsName = "CapacitorAppleMaps"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "create", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setCamera", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getMapBounds", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCameraPosition", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "fitBounds", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addMarkers", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addMarker", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateMarkers", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeMarkers", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeMarker", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableClustering", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disableClustering", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addPolylines", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addPolygons", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addCircles", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeOverlays", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setMapType", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getMapType", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableCurrentLocation", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTrafficEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setPointsOfInterestEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setCompassEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setScaleEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setColorScheme", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setGestures", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setPadding", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "takeSnapshot", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "searchAutocomplete", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "searchPlaces", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "searchResolve", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "reverseGeocode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "geocode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "onResize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "onDisplay", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "onScroll", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise)
    ]

    var maps = [String: Map]()
    private let searchService = SearchService()
    private let geocodeService = GeocodeService()

    // MARK: - Location permission
    //
    // Backing state for the `location` permission alias. The check/request
    // implementations and the CLLocationManagerDelegate callback live in
    // Permissions.swift. The manager is created lazily on first use so a plugin
    // that never touches location never instantiates one.
    var locationManager: CLLocationManager?
    /// Callback id of the in-flight `requestPermissions` call, held while the
    /// system prompt is up so the delegate can resolve it once the user answers.
    var permissionCallID: String?

    // MARK: - App lifecycle

    override public func load() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// After the app returns to the foreground WebKit can rebuild its scroll-view
    /// hierarchy, orphaning the native map's touch handling (it still renders but
    /// gestures stop working). Re-mount each map into its current container.
    @objc private func handleDidBecomeActive() {
        for (_, map) in maps {
            map.remountIntoContainer()
        }
    }

    // MARK: - Lifecycle

    @objc func create(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.reject("id is required", PluginError.invalidArgument)
            return
        }
        guard let configObj = call.getObject("config") else {
            call.reject("config is required", PluginError.invalidArgument)
            return
        }
        let forceCreate = call.getBool("forceCreate", false)

        do {
            let config = try AppleMapConfig(fromJSObject: configObj)

            if maps[id] != nil {
                if !forceCreate {
                    call.resolve()
                    return
                }
                maps.removeValue(forKey: id)?.destroy()
            }

            runOnMainSync {
                self.maps[id] = Map(id: id, config: config, delegate: self)
            }
            call.resolve()
        } catch {
            call.reject(error.localizedDescription, PluginError.operationFailed, error)
        }
    }

    @objc func destroy(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps.removeValue(forKey: id) else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.destroy()
        call.resolve()
    }

    // MARK: - Camera

    @objc func setCamera(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        runOnMainSync {
            map.setCamera(from: call.getObject("config") ?? [:])
        }
        call.resolve()
    }

    @objc func getMapBounds(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        runOnMainSync {
            call.resolve(map.boundsPayload())
        }
    }

    @objc func getCameraPosition(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        runOnMainSync {
            call.resolve(map.cameraPayload())
        }
    }

    @objc func fitBounds(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let boundsObj = call.getObject("bounds"),
              let swObj = boundsObj["southwest"] as? JSObject,
              let swLat = swObj["lat"] as? Double, let swLng = swObj["lng"] as? Double,
              let neObj = boundsObj["northeast"] as? JSObject,
              let neLat = neObj["lat"] as? Double, let neLng = neObj["lng"] as? Double else {
            call.reject("bounds with southwest and northeast is required", PluginError.invalidArgument)
            return
        }
        let padding = call.getDouble("padding") ?? 0
        let animate = call.getBool("animate", true)
        map.fitBounds(
            southwest: CLLocationCoordinate2D(latitude: swLat, longitude: swLng),
            northeast: CLLocationCoordinate2D(latitude: neLat, longitude: neLng),
            padding: padding, animate: animate
        )
        call.resolve()
    }

    // MARK: - Markers
    //
    // The marker + clustering bridge methods live in MarkerBridge.swift to keep
    // this type within SwiftLint's body-length budget.

    // MARK: - Search

    @objc func searchAutocomplete(_ call: CAPPluginCall) {
        searchService.autocomplete(call)
    }

    @objc func searchPlaces(_ call: CAPPluginCall) {
        searchService.places(call)
    }

    @objc func searchResolve(_ call: CAPPluginCall) {
        searchService.resolve(call)
    }

    // MARK: - Geocoding

    @objc func reverseGeocode(_ call: CAPPluginCall) {
        geocodeService.reverse(call)
    }

    @objc func geocode(_ call: CAPPluginCall) {
        geocodeService.forward(call)
    }

    // MARK: - MKMapViewDelegate
    //
    // The region-change delegate methods (onCameraMoveStarted / onCameraIdle and
    // the min/max-zoom bounce) live in CameraEvents.swift to keep this type within
    // SwiftLint's body-length budget.

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        findMap(for: mapView)?.annotationView(for: annotation, in: mapView)
    }

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let map = findMap(for: mapView) else { return }

        if let cluster = view.annotation as? MKClusterAnnotation {
            notifyListeners("onClusterClick", data: [
                "mapId": map.id,
                "latitude": cluster.coordinate.latitude,
                "longitude": cluster.coordinate.longitude,
                "count": cluster.memberAnnotations.count,
                "markerIds": cluster.memberAnnotations.compactMap { ($0 as? AppleMapMarker)?.markerId }
            ])
            map.expandCluster(cluster, in: mapView)
            return
        }

        if view.annotation is MKUserLocation {
            let coordinate = view.annotation?.coordinate ?? mapView.userLocation.coordinate
            notifyListeners("onMyLocationClick", data: [
                "mapId": map.id,
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude
            ])
            mapView.deselectAnnotation(view.annotation, animated: false)
            return
        }

        guard let marker = view.annotation as? AppleMapMarker else { return }
        notifyListeners("onMarkerClick", data: [
            "mapId": map.id,
            "markerId": marker.markerId,
            "latitude": marker.coordinate.latitude,
            "longitude": marker.coordinate.longitude,
            "title": marker.title ?? ""
        ])
        map.handleMarkerSelection(marker)
    }

    // MARK: - Helpers

    func findMap(for mapView: MKMapView) -> Map? {
        for (_, map) in maps where map.mapView === mapView {
            return map
        }
        return nil
    }
}
