import Foundation
import MapKit
import Capacitor

// MARK: - Annotation
//
// Split out of CapacitorAppleMaps.swift to keep the core Map type within
// SwiftLint's length budget. The marker model plus the payload parsing that is
// specific to a marker (icon fields, anchor), so makeMarker/updateMarkers on the
// Map stay small.

/// A map pin carrying a stable id echoed back to JS on tap. The id is generated
/// unless the caller supplied one in the marker payload.
class AppleMapMarker: MKPointAnnotation {
    var markerId: String = UUID().uuidString
    var iconUrl: String?
    var iconSize: CGSize?
    /// Where the icon image is pinned to the coordinate, in 0..1 fractions from
    /// the image's top-left. `nil` keeps the bottom-centre default (a teardrop
    /// pin's tip); `(0.5, 0.5)` centres the image, as a dot wants.
    var iconAnchor: CGPoint?
    /// When true the pin can be dragged (press-and-hold, then move), emitting the
    /// `onMarkerDrag*` events. Dragging is driven by a long-press recognizer on the
    /// map rather than `MKAnnotationView.isDraggable`, so intermediate coordinates
    /// stream to JS instead of only the drop point.
    var isDraggable = false
    /// Marker opacity 0..1, applied to the annotation view's `alpha`. Defaults to 1.
    var opacity: CGFloat = 1
    /// Tint for the default MapKit pin (`MKMarkerAnnotationView.markerTintColor`).
    /// Ignored for image markers, which carry their own colors. nil = MapKit default.
    var tintColor: UIColor?
    /// Draw order relative to other markers (higher draws on top), mapped to
    /// `MKAnnotationView.zPriority`. Defaults to 0.
    var zIndex: Double = 0

    /// The `MKAnnotationView.centerOffset` that lands this marker's anchor point on
    /// its coordinate, for an icon rendered at `imageSize`. A view is centred on
    /// its coordinate by default, so the offset moves the view until the anchor —
    /// not the centre — sits on the point. The bottom-centre default `(0.5, 1)`
    /// gives `(0, -height/2)`, the classic teardrop-tip anchoring.
    func centerOffset(for imageSize: CGSize) -> CGPoint {
        let anchor = iconAnchor ?? CGPoint(x: 0.5, y: 1.0)
        return CGPoint(x: imageSize.width * (0.5 - anchor.x),
                       y: imageSize.height * (0.5 - anchor.y))
    }

    /// Applies whichever icon fields (`iconUrl`, `iconSize`, `iconAnchor`) are
    /// present in an update payload, returning whether any changed — the caller
    /// re-renders the annotation when so. A present `iconAnchor` of `null` resets
    /// to the bottom-centre default. Mirrors the parsing in `Map.makeMarker`.
    func applyIconUpdates(from obj: JSObject) -> Bool {
        var changed = false
        if obj.keys.contains("iconUrl") {
            iconUrl = obj["iconUrl"] as? String
            changed = true
        }
        if let size = AppleMapMarker.parseSize(obj["iconSize"]) {
            iconSize = size
            changed = true
        }
        if obj.keys.contains("iconAnchor") {
            iconAnchor = AppleMapMarker.parseAnchor(obj["iconAnchor"])
            changed = true
        }
        return changed
    }

    /// A `{ width, height }` payload as a `CGSize`, or nil when absent/malformed.
    static func parseSize(_ value: Any?) -> CGSize? {
        guard let obj = value as? JSObject,
              let width = obj["width"] as? Double,
              let height = obj["height"] as? Double else { return nil }
        return CGSize(width: width, height: height)
    }

    /// A `{ x, y }` anchor payload as a `CGPoint`, or nil when absent/malformed.
    static func parseAnchor(_ value: Any?) -> CGPoint? {
        guard let obj = value as? JSObject,
              let x = obj["x"] as? Double,
              let y = obj["y"] as? Double else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// A `{ r, g, b, a }` payload (each channel 0..255, `a` optional) as a
    /// `UIColor`, or nil when absent/malformed.
    static func parseTintColor(_ value: Any?) -> UIColor? {
        guard let obj = value as? JSObject,
              let red = obj["r"] as? Double,
              let green = obj["g"] as? Double,
              let blue = obj["b"] as? Double else { return nil }
        let alpha = obj["a"] as? Double ?? 255
        return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha / 255)
    }
}
