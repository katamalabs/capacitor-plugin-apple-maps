import Foundation
import MapKit
import UIKit
import Capacitor

// MARK: - Map: overlays, appearance, tap, helpers
//
// Split out of CapacitorAppleMaps.swift so the core Map type stays within
// SwiftLint's body-length budget. These are still part of the same Map type.

extension Map {

    // MARK: Overlays

    func addPolylines(_ objs: [JSObject]) -> [String] {
        var ids: [String] = []
        runOnMainSync {
            for obj in objs {
                let coords = Map.parseCoords(obj["path"])
                guard coords.count >= 2 else { continue }
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                let style = Map.overlayStyle(from: obj, defaultLineWidth: 3, filled: false)
                ids.append(self.register(polyline, style: style))
            }
        }
        return ids
    }

    func addPolygons(_ objs: [JSObject]) -> [String] {
        var ids: [String] = []
        runOnMainSync {
            for obj in objs {
                let rings = Map.parseRings(obj["paths"])
                guard let exterior = rings.first, exterior.count >= 3 else { continue }
                let holes = rings.dropFirst().map { MKPolygon(coordinates: $0, count: $0.count) }
                let polygon = MKPolygon(
                    coordinates: exterior, count: exterior.count,
                    interiorPolygons: holes.isEmpty ? nil : Array(holes)
                )
                let style = Map.overlayStyle(from: obj, defaultLineWidth: 2, filled: true)
                ids.append(self.register(polygon, style: style))
            }
        }
        return ids
    }

    func addCircles(_ objs: [JSObject]) -> [String] {
        var ids: [String] = []
        runOnMainSync {
            for obj in objs {
                guard let centerObj = obj["center"] as? JSObject,
                      let lat = centerObj["lat"] as? Double,
                      let lng = centerObj["lng"] as? Double,
                      let radius = obj["radius"] as? Double else { continue }
                let circle = MKCircle(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    radius: radius
                )
                let style = Map.overlayStyle(from: obj, defaultLineWidth: 2, filled: true)
                ids.append(self.register(circle, style: style))
            }
        }
        return ids
    }

    func removeOverlays(_ ids: [String]) {
        runOnMainSync {
            for id in ids {
                if let overlay = self.overlays.removeValue(forKey: id) {
                    self.mapView.removeOverlay(overlay)
                    self.overlayStyles.removeValue(forKey: ObjectIdentifier(overlay))
                }
            }
        }
    }

    /// Store an overlay + its style under a fresh id and add it to the map. Must
    /// be called on the main thread.
    private func register(_ overlay: MKOverlay, style: OverlayStyle) -> String {
        let id = UUID().uuidString
        overlays[id] = overlay
        overlayStyles[ObjectIdentifier(overlay)] = style
        mapView.addOverlay(overlay)
        return id
    }

    // Appearance / location / gestures / padding live in Appearance.swift.

    // MARK: Map tap

    /// Emits `onMapClick` for taps on the map surface. Taps that land on a marker
    /// never reach here (the gesture delegate declines them) so MapKit alone
    /// selects the pin and shows its callout / info window; `onMarkerClick` fires
    /// from `didSelect`.
    @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // A tap on the bare map closes any open info window.
        dismissCallout()
        emitMapGesture("onMapClick", at: gesture.location(in: mapView))
    }

    /// The marker under `point`, if the point landed on one (any marker, draggable
    /// or not); nil for the map surface or a cluster bubble.
    private func markerAnnotation(at point: CGPoint) -> AppleMapMarker? {
        var view = mapView.hitTest(point, with: nil)
        while let current = view {
            if let annotationView = current as? MKAnnotationView,
               let marker = annotationView.annotation as? AppleMapMarker {
                return marker
            }
            view = current.superview
        }
        return nil
    }

    /// Emits `onMapLongClick` for a long-press on the map surface. A long-press
    /// recognizer reports `.began` once when the press threshold is reached.
    @objc func handleMapLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        emitMapGesture("onMapLongClick", at: gesture.location(in: mapView))
    }

    /// Converts a view point to a coordinate and notifies `event`, unless the
    /// point landed on an annotation (marker selection reports those separately).
    private func emitMapGesture(_ event: String, at point: CGPoint) {
        var view = mapView.hitTest(point, with: nil)
        while let current = view {
            if current is MKAnnotationView { return }
            view = current.superview
        }
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        delegate?.notifyListeners(event, data: [
            "mapId": id,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ])
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    /// Decide which of our recognizers may claim a given touch. The marker-drag
    /// recognizer wants touches only on a *draggable* pin. The tap and
    /// map-long-press recognizers decline touches on *any* marker, so MapKit's own
    /// selection runs and presents the pin's callout (info window) - relaying it
    /// through our own tap recognizer raced with MapKit's and cancelled the
    /// selection, so the callout never showed. Both still fire for the bare map
    /// surface.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        let marker = markerAnnotation(at: touch.location(in: mapView))
        if gestureRecognizer.name == Map.markerDragGestureName {
            return marker?.isDraggable ?? false
        }
        // A tap on the info-window bubble must not reach the map tap handler (which
        // dismisses it); the bubble's own recognizer emits onInfoWindowClick.
        if let callout = calloutView, touch.view?.isDescendant(of: callout) ?? false {
            return false
        }
        return marker == nil
    }

    // MARK: Marker drag

    /// Drives dragging of `draggable` markers. On `.began` a press that lands on a
    /// draggable pin picks it up and freezes the map; each `.changed` moves the
    /// pin and streams `onMarkerDrag`; the end states drop it and restore the map.
    @objc func handleMarkerDrag(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: mapView)
        switch gesture.state {
        case .began:
            guard let marker = draggableMarker(at: point) else { return }
            draggingMarker = marker
            scrollWasEnabledBeforeDrag = mapView.isScrollEnabled
            mapView.isScrollEnabled = false
            emitMarkerDrag("onMarkerDragStart", for: marker)
        case .changed:
            guard let marker = draggingMarker else { return }
            marker.coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            emitMarkerDrag("onMarkerDrag", for: marker)
        case .ended, .cancelled, .failed:
            guard let marker = draggingMarker else { return }
            emitMarkerDrag("onMarkerDragEnd", for: marker)
            mapView.isScrollEnabled = scrollWasEnabledBeforeDrag
            draggingMarker = nil
        default:
            break
        }
    }

    /// The draggable marker under `point`, if any; nil for the map surface, a
    /// cluster bubble, or a non-draggable pin.
    private func draggableMarker(at point: CGPoint) -> AppleMapMarker? {
        guard let marker = markerAnnotation(at: point), marker.isDraggable else { return nil }
        return marker
    }

    private func emitMarkerDrag(_ event: String, for marker: AppleMapMarker) {
        delegate?.notifyListeners(event, data: [
            "mapId": id,
            "markerId": marker.markerId,
            "latitude": marker.coordinate.latitude,
            "longitude": marker.coordinate.longitude
        ])
    }

    // MARK: Static helpers

    /// Resolves an overlay's stroke/fill styling from its payload, applying the
    /// per-shape default line width and dropping the fill for unfilled shapes
    /// (polylines). Pure, so overlay styling can be unit-tested.
    static func overlayStyle(from obj: JSObject, defaultLineWidth: Double, filled: Bool) -> OverlayStyle {
        OverlayStyle(
            strokeColor: color(obj["strokeColor"], opacity: obj["strokeOpacity"]) ?? .systemBlue,
            lineWidth: CGFloat(obj["strokeWeight"] as? Double ?? defaultLineWidth),
            fillColor: filled ? color(obj["fillColor"], opacity: obj["fillOpacity"]) : nil
        )
    }

    /// Parses a flat array of `{lat,lng}` objects into coordinates.
    static func parseCoords(_ value: Any?) -> [CLLocationCoordinate2D] {
        guard let arr = value as? [Any] else { return [] }
        return arr.compactMap { item in
            guard let obj = item as? JSObject,
                  let lat = obj["lat"] as? Double,
                  let lng = obj["lng"] as? Double else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    /// Parses a polygon `paths` value: either a single ring of coordinates or an
    /// array of rings (exterior first, then holes).
    static func parseRings(_ value: Any?) -> [[CLLocationCoordinate2D]] {
        guard let arr = value as? [Any] else { return [] }
        if let first = arr.first, first is [Any] {
            return arr.compactMap { ($0 as? [Any]).map { parseCoords($0) } }
        }
        return [parseCoords(arr)]
    }

    /// Parses a `#RGB`/`#RRGGBB`/`#RRGGBBAA` hex string, overriding the alpha with
    /// `opacity` (0..1) when supplied. Returns nil for a missing/malformed value.
    static func color(_ value: Any?, opacity: Any?) -> UIColor? {
        guard let hex = value as? String else { return nil }
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard let intVal = UInt64(str, radix: 16) else { return nil }

        let red, green, blue: Double
        var alpha: Double = 1
        switch str.count {
        case 8:
            red = Double((intVal & 0xFF00_0000) >> 24) / 255
            green = Double((intVal & 0x00FF_0000) >> 16) / 255
            blue = Double((intVal & 0x0000_FF00) >> 8) / 255
            alpha = Double(intVal & 0x0000_00FF) / 255
        case 6:
            red = Double((intVal & 0xFF0000) >> 16) / 255
            green = Double((intVal & 0x00FF00) >> 8) / 255
            blue = Double(intVal & 0x0000FF) / 255
        default:
            return nil
        }
        if let alphaOverride = opacity as? Double { alpha = alphaOverride }
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Plugin: overlay + appearance bridge and the overlay renderer

extension CapacitorAppleMapsPlugin {

    @objc func addPolylines(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let objs = call.getArray("polylines") as? [JSObject] else {
            call.reject("polylines array is required", PluginError.invalidArgument)
            return
        }
        call.resolve(["ids": map.addPolylines(objs)])
    }

    @objc func addPolygons(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let objs = call.getArray("polygons") as? [JSObject] else {
            call.reject("polygons array is required", PluginError.invalidArgument)
            return
        }
        call.resolve(["ids": map.addPolygons(objs)])
    }

    @objc func addCircles(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let objs = call.getArray("circles") as? [JSObject] else {
            call.reject("circles array is required", PluginError.invalidArgument)
            return
        }
        call.resolve(["ids": map.addCircles(objs)])
    }

    @objc func removeOverlays(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let ids = call.getArray("ids") as? [String] else {
            call.reject("ids array is required", PluginError.invalidArgument)
            return
        }
        map.removeOverlays(ids)
        call.resolve()
    }

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let style = findMap(for: mapView)?.overlayStyles[ObjectIdentifier(overlay)]

        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = style?.strokeColor ?? .systemBlue
            renderer.lineWidth = style?.lineWidth ?? 3
            return renderer
        }
        if let polygon = overlay as? MKPolygon {
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.strokeColor = style?.strokeColor ?? .systemBlue
            renderer.lineWidth = style?.lineWidth ?? 2
            renderer.fillColor = style?.fillColor
            return renderer
        }
        if let circle = overlay as? MKCircle {
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = style?.strokeColor ?? .systemBlue
            renderer.lineWidth = style?.lineWidth ?? 2
            renderer.fillColor = style?.fillColor
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
