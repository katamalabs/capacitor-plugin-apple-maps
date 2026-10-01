import Foundation
import MapKit
import Capacitor
import WebKit
import UIKit

// MARK: - Errors

enum AppleMapsError: Error, LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}

// MARK: - Zoom <-> region conversion
//
// MapKit has no notion of a Google-style integer zoom; it works in region
// spans. These helpers convert between the two using the web-mercator tile
// relationship: the whole world (360°) is `256 * 2^zoom` points wide, so a
// viewport `widthPoints` points wide spans `360 * widthPoints / (256 * 2^zoom)`
// degrees of longitude. The round trip is approximate - MapKit adjusts spans to
// the view's aspect ratio - which is fine for the host app's radius estimates.

func zoomToLongitudeDelta(_ zoom: Double, widthPoints: Double) -> Double {
    let width = widthPoints > 0 ? widthPoints : 256.0
    return 360.0 * width / (256.0 * pow(2.0, zoom))
}

func longitudeDeltaToZoom(_ delta: Double, widthPoints: Double) -> Double {
    let width = widthPoints > 0 ? widthPoints : 256.0
    let safeDelta = delta > 0 ? delta : 0.0001
    return log2(360.0 * width / (256.0 * safeDelta))
}

/// Clamps a Google-style zoom to an optional `[minZoom, maxZoom]` range. A nil
/// bound means unbounded on that side; if `minZoom > maxZoom` the ceiling wins.
/// Pure so the clamp behavior can be unit-tested without an `MKMapView`.
func clampZoom(_ zoom: Double, minZoom: Double?, maxZoom: Double?) -> Double {
    var result = max(zoom, minZoom ?? -Double.greatestFiniteMagnitude)
    result = min(result, maxZoom ?? Double.greatestFiniteMagnitude)
    return result
}

/// The smallest `MKMapRect` containing both corners, regardless of their relative
/// orientation (latitude grows north but `MKMapPoint.y` grows south). Pure so the
/// `fitBounds` framing math can be unit-tested without an `MKMapView`.
func boundingMapRect(southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D) -> MKMapRect {
    let swPoint = MKMapPoint(southwest)
    let nePoint = MKMapPoint(northeast)
    return MKMapRect(
        x: min(swPoint.x, nePoint.x),
        y: min(swPoint.y, nePoint.y),
        width: abs(swPoint.x - nePoint.x),
        height: abs(swPoint.y - nePoint.y)
    )
}

/// The corner coordinates of a region, used to report the visible bounds to JS.
/// Pure function so it can be unit-tested without an `MKMapView`.
func regionCorners(center: CLLocationCoordinate2D, span: MKCoordinateSpan)
-> (southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D) {
    let southwest = CLLocationCoordinate2D(
        latitude: center.latitude - span.latitudeDelta / 2,
        longitude: center.longitude - span.longitudeDelta / 2
    )
    let northeast = CLLocationCoordinate2D(
        latitude: center.latitude + span.latitudeDelta / 2,
        longitude: center.longitude + span.longitudeDelta / 2
    )
    return (southwest, northeast)
}

// MARK: - Annotation
//
// The pin model, `AppleMapMarker`, lives in AppleMapMarker.swift (kept there so
// this file stays within SwiftLint's length budget).

/// Stroke/fill styling for an overlay, resolved from the JS payload and looked
/// up by the map's `rendererFor` delegate when MapKit asks how to draw it.
struct OverlayStyle {
    var strokeColor: UIColor
    var lineWidth: CGFloat
    var fillColor: UIColor?
    /// Dash pattern (on/off point lengths) for the stroke, or nil for a solid line.
    var lineDashPattern: [NSNumber]?
}

// MARK: - Config

struct AppleMapConfig {
    let center: CLLocationCoordinate2D
    let zoom: Double
    let minZoom: Double?
    let maxZoom: Double?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let clustering: Bool
    let mapType: String
    let showInfoWindows: Bool
    let showsTraffic: Bool
    let showsPointsOfInterest: Bool
    let showsCompass: Bool
    let showsScale: Bool
    let showsBuildings: Bool
    let colorScheme: String
    let scrollEnabled: Bool
    let zoomEnabled: Bool
    let rotateEnabled: Bool
    let pitchEnabled: Bool
    let padding: UIEdgeInsets

    init(fromJSObject obj: JSObject) throws {
        guard let centerObj = obj["center"] as? JSObject,
              let lat = centerObj["lat"] as? Double,
              let lng = centerObj["lng"] as? Double else {
            throw AppleMapsError.invalidArguments("config.center is missing or malformed")
        }
        self.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        self.zoom = obj["zoom"] as? Double ?? 12
        self.minZoom = obj["minZoom"] as? Double
        self.maxZoom = obj["maxZoom"] as? Double
        self.width = obj["width"] as? Double ?? 0
        self.height = obj["height"] as? Double ?? 0
        self.x = obj["x"] as? Double ?? 0
        self.y = obj["y"] as? Double ?? 0
        self.clustering = obj["clustering"] as? Bool ?? false
        self.mapType = obj["mapType"] as? String ?? "standard"
        self.showInfoWindows = obj["showInfoWindows"] as? Bool ?? false
        // Defaults mirror MapKit's own (traffic/scale off, POI/compass on).
        self.showsTraffic = obj["showsTraffic"] as? Bool ?? false
        self.showsPointsOfInterest = obj["showsPointsOfInterest"] as? Bool ?? true
        self.showsCompass = obj["showsCompass"] as? Bool ?? true
        self.showsScale = obj["showsScale"] as? Bool ?? false
        self.showsBuildings = obj["showsBuildings"] as? Bool ?? true
        self.colorScheme = obj["colorScheme"] as? String ?? "default"
        let gestures = obj["gestures"] as? JSObject ?? [:]
        self.scrollEnabled = gestures["scroll"] as? Bool ?? true
        self.zoomEnabled = gestures["zoom"] as? Bool ?? true
        self.rotateEnabled = gestures["rotate"] as? Bool ?? true
        self.pitchEnabled = gestures["pitch"] as? Bool ?? true
        self.padding = AppleMapConfig.parsePadding(obj["padding"])
    }
}

// MARK: - Map

/// Owns one native `MKMapView` and mounts it into the WKWebView's view tree at
/// the bound element's location, mirroring the compositing approach of
/// `@capacitor/google-maps`.
public class Map: NSObject, UIGestureRecognizerDelegate {
    static let mapTag = 99999
    /// Name given to the marker-drag long-press recognizer, so the gesture
    /// delegate can let it receive touches on a marker while the map-surface
    /// recognizers decline them (letting MapKit select the pin / show its callout).
    static let markerDragGestureName = "capacitorAppleMapMarkerDrag"

    let id: String
    var config: AppleMapConfig
    let mapView: MKMapView

    var markers: [String: AppleMapMarker] = [:]
    /// Overlays keyed by the id handed back to JS, for removal.
    var overlays: [String: MKOverlay] = [:]
    /// Overlay styling keyed by the overlay instance, read back in `rendererFor`.
    var overlayStyles: [ObjectIdentifier: OverlayStyle] = [:]
    private(set) var clusteringEnabled = false
    /// Best-effort lower bound on the total marker count before clustering applies.
    /// MapKit has no per-cluster minimum, so this gates clustering on the number of
    /// markers present when each annotation view is built. See enableClustering.
    var clusterMinSize = 2
    /// Whether an annotation view should cluster right now, given the toggle and count.
    var shouldCluster: Bool { clusteringEnabled && markers.count >= clusterMinSize }

    /// Guards against a feedback loop when we programmatically clamp the region
    /// back to the minimum zoom inside `regionDidChange`.
    var isAdjustingRegion = false

    /// The custom info-window bubble currently shown (a plain subview of the map,
    /// since MapKit's own callout doesn't render when the map is composited inside
    /// the web view), the marker it points at, and a display link that keeps it
    /// glued to the pin as the map pans/zooms. See Callout.swift.
    var calloutView: UIView?
    var calloutMarker: AppleMapMarker?
    var calloutDisplayLink: CADisplayLink?

    /// The marker currently being dragged (via the map's long-press recognizer),
    /// or nil when no drag is in progress.
    var draggingMarker: AppleMapMarker?
    /// The map's `isScrollEnabled` value before a drag disabled it, restored when
    /// the drag ends.
    var scrollWasEnabledBeforeDrag = true

    /// Edge insets from `setPadding`, added to the `fitBounds` framing so it
    /// respects the padding the caller asked for.
    var contentInsets: UIEdgeInsets = .zero

    /// Retains the in-flight `MKMapSnapshotter` for the duration of `takeSnapshot`.
    var pendingSnapshotter: MKMapSnapshotter?

    /// The user-tracking button (recenter/follow control) when shown, so it can be
    /// removed again. See setUserTrackingButton in MapControls.swift.
    var userTrackingButton: MKUserTrackingButton?

    weak var delegate: CapacitorAppleMapsPlugin?
    var targetView: UIView?
    /// Reports the initial mount; cleared once called so it fires exactly once.
    var mountCompletion: ((MountOutcome) -> Void)?
    var isDestroyed = false
    /// The web view's child scroll view for the element can appear a few frames
    /// after JS asks for the map, so mounting is retried before it's declared
    /// failed: up to `mountAttempts` tries, `mountRetryInterval` apart (~1s).
    static let mountAttempts = 20
    static let mountRetryInterval: TimeInterval = 0.05
    /// Decoded marker icons keyed by their url/asset string. `NSCache` bounds the
    /// footprint and evicts under memory pressure, unlike a plain dictionary that
    /// would grow without limit as icons come and go. Read/written in MarkerIcons.
    let iconCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()
    /// Remote icon urls with a download in flight, so a re-render (e.g. a
    /// clustering toggle re-adding every annotation) doesn't start a duplicate.
    var inFlightIconURLs: Set<String> = []
    /// Remote icon urls that returned a response but no usable image - a permanent
    /// miss we must not retry on every re-render (a transport error is left out so
    /// a later render can retry it).
    var failedIconURLs: Set<String> = []

    init(id: String, config: AppleMapConfig, delegate: CapacitorAppleMapsPlugin,
         onMount: ((MountOutcome) -> Void)? = nil) {
        self.id = id
        self.config = config
        self.mapView = MKMapView()
        self.delegate = delegate
        self.mountCompletion = onMount
        super.init()
        // Start clustered when the caller asked for it, so markers added later
        // cluster on their first render instead of flashing as individual pins.
        self.clusteringEnabled = config.clustering
        self.render()
    }

    private func render() {
        DispatchQueue.main.async {
            self.mapView.delegate = self.delegate
            self.mapView.showsUserLocation = false
            self.mapView.mapType = Map.mapType(from: self.config.mapType)
            self.applyAppearance(self.config)
            self.mapView.isScrollEnabled = self.config.scrollEnabled
            self.mapView.isZoomEnabled = self.config.zoomEnabled
            self.mapView.isRotateEnabled = self.config.rotateEnabled
            self.mapView.isPitchEnabled = self.config.pitchEnabled
            self.mapView.layoutMargins = self.config.padding
            self.contentInsets = self.config.padding
            self.mapView.frame = CGRect(x: self.config.x, y: self.config.y, width: self.config.width, height: self.config.height)
            self.setCameraInternal(coordinate: self.config.center, zoom: self.config.zoom, animate: false)

            // Emit onMapClick for taps that don't land on a marker. cancelsTouchesInView
            // stays false and the delegate allows simultaneous recognition so this
            // never swallows MapKit's own pan/zoom or marker-selection gestures.
            let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleMapTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            self.mapView.addGestureRecognizer(tap)

            // Emit onMapLongClick for a long-press that doesn't land on a marker.
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.handleMapLongPress(_:)))
            longPress.cancelsTouchesInView = false
            longPress.delegate = self
            self.mapView.addGestureRecognizer(longPress)

            // Drives marker dragging: a long-press that lands on a draggable pin
            // picks it up; subsequent movement streams onMarkerDrag. Presses that
            // miss a draggable pin are ignored here and handled by the long-press
            // recognizer above.
            let markerDrag = UILongPressGestureRecognizer(target: self, action: #selector(self.handleMarkerDrag(_:)))
            markerDrag.cancelsTouchesInView = false
            markerDrag.name = Map.markerDragGestureName
            markerDrag.delegate = self
            self.mapView.addGestureRecognizer(markerDrag)

            self.mount(attempt: 1)
        }
    }

    func destroy() {
        DispatchQueue.main.async {
            self.isDestroyed = true
            self.finishMount(.destroyed)
            self.dismissCallout()
            self.mapView.removeFromSuperview()
            self.mapView.delegate = nil
            self.targetView?.tag = 0
        }
    }

    // MARK: Camera

    /// Must be called on the main thread. `bearing` (heading, degrees clockwise
    /// from north) and `pitch` (tilt, degrees from top-down) are applied on top of
    /// the region/center change when supplied; nil leaves that axis unchanged.
    func setCameraInternal(
        coordinate: CLLocationCoordinate2D?,
        zoom: Double?,
        animate: Bool,
        bearing: Double? = nil,
        pitch: Double? = nil
    ) {
        let center = coordinate ?? mapView.centerCoordinate

        if let zoom = zoom {
            // Enforce the zoom range: a smaller zoom means a wider span (minZoom is the
            // zoom-out floor), a larger zoom a tighter one (maxZoom is the zoom-in ceiling).
            let clampedZoom = clampZoom(zoom, minZoom: config.minZoom, maxZoom: config.maxZoom)

            let width = Double(mapView.bounds.width > 0 ? mapView.bounds.width : UIScreen.main.bounds.width)
            let height = Double(mapView.bounds.height > 0 ? mapView.bounds.height : UIScreen.main.bounds.height)
            let lonDelta = min(zoomToLongitudeDelta(clampedZoom, widthPoints: width), 360.0)
            let latDelta = min(lonDelta * (height / max(width, 1)), 180.0)
            let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            let region = mapView.regionThatFits(MKCoordinateRegion(center: center, span: span))
            mapView.setRegion(region, animated: animate)
        } else if coordinate != nil {
            mapView.setCenter(center, animated: animate)
        }

        // Rotation/tilt ride on top of the region change, preserving the resulting
        // center and distance. Reading the camera after the region set gives the
        // new center/zoom to build on.
        if bearing != nil || pitch != nil, let camera = mapView.camera.copy() as? MKMapCamera {
            if let bearing = bearing { camera.heading = bearing }
            if let pitch = pitch { camera.pitch = CGFloat(max(0, pitch)) }
            mapView.setCamera(camera, animated: animate)
        }
    }

    /// Frame `southwest`..`northeast` in the viewport, inset by `padding` points.
    func fitBounds(southwest: CLLocationCoordinate2D, northeast: CLLocationCoordinate2D, padding: Double, animate: Bool) {
        let rect = boundingMapRect(southwest: southwest, northeast: northeast)
        runOnMainSync {
            // Combine the per-call padding with any standing content insets (setPadding).
            let inset = UIEdgeInsets(
                top: padding + self.contentInsets.top,
                left: padding + self.contentInsets.left,
                bottom: padding + self.contentInsets.bottom,
                right: padding + self.contentInsets.right
            )
            self.mapView.setVisibleMapRect(rect, edgePadding: inset, animated: animate)
        }
    }

    // MARK: Markers

    func addMarkers(_ markerObjs: [JSObject]) -> [String] {
        var ids: [String] = []
        runOnMainSync {
            var toAdd: [AppleMapMarker] = []
            var toRemove: [AppleMapMarker] = []
            for obj in markerObjs {
                guard let marker = Map.makeMarker(from: obj) else { continue }
                // Re-adding an existing id replaces that pin. Without this the old
                // annotation stays on the map but drops out of `markers`, leaving
                // an orphan that removeMarkers can never reach.
                if let existing = self.markers[marker.markerId] {
                    if let pending = toAdd.firstIndex(where: { $0 === existing }) {
                        toAdd.remove(at: pending)
                    } else {
                        toRemove.append(existing)
                    }
                }
                self.markers[marker.markerId] = marker
                toAdd.append(marker)
                ids.append(marker.markerId)
            }
            self.mapView.removeAnnotations(toRemove)
            self.mapView.addAnnotations(toAdd)
        }
        return ids
    }

    /// Builds an annotation from a marker payload, or nil if the coordinate is
    /// missing/malformed. Pure (no `MKMapView`), so it can be unit-tested.
    static func makeMarker(from obj: JSObject) -> AppleMapMarker? {
        guard let coordObj = obj["coordinate"] as? JSObject,
              let lat = coordObj["lat"] as? Double,
              let lng = coordObj["lng"] as? Double else { return nil }
        let marker = AppleMapMarker()
        if let customId = obj["markerId"] as? String, !customId.isEmpty {
            marker.markerId = customId
        }
        marker.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        marker.title = obj["title"] as? String
        marker.subtitle = obj["snippet"] as? String
        marker.iconUrl = obj["iconUrl"] as? String
        marker.isDraggable = obj["draggable"] as? Bool ?? false
        marker.iconSize = AppleMapMarker.parseSize(obj["iconSize"])
        marker.iconAnchor = AppleMapMarker.parseAnchor(obj["iconAnchor"])
        if let opacity = obj["opacity"] as? Double { marker.opacity = CGFloat(opacity) }
        marker.tintColor = AppleMapMarker.parseTintColor(obj["tintColor"])
        if let zIndex = obj["zIndex"] as? Double { marker.zIndex = zIndex }
        return marker
    }

    func removeMarkers(_ ids: [String]) {
        runOnMainSync {
            var toRemove: [AppleMapMarker] = []
            for id in ids {
                if let marker = self.markers[id] {
                    toRemove.append(marker)
                    self.markers.removeValue(forKey: id)
                }
            }
            self.mapView.removeAnnotations(toRemove)
        }
    }

    /// Apply partial changes to existing markers. A moved marker animates to its
    /// new coordinate; an icon change re-adds the annotation so `viewFor` reruns.
    func updateMarkers(_ objs: [JSObject]) {
        runOnMainSync {
            var toRefresh: [AppleMapMarker] = []
            for obj in objs {
                guard let markerId = obj["markerId"] as? String,
                      let marker = self.markers[markerId] else { continue }

                if let coordObj = obj["coordinate"] as? JSObject,
                   let lat = coordObj["lat"] as? Double,
                   let lng = coordObj["lng"] as? Double {
                    UIView.animate(withDuration: 0.25) {
                        marker.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    }
                }
                if obj.keys.contains("title") {
                    marker.title = obj["title"] as? String
                }
                if obj.keys.contains("snippet") {
                    marker.subtitle = obj["snippet"] as? String
                }
                if obj.keys.contains("draggable") {
                    // The drag gate reads this flag live, so no view rebuild is
                    // needed to enable/disable dragging.
                    marker.isDraggable = obj["draggable"] as? Bool ?? false
                }
                // Opacity / tint / z-order are applied to the live annotation view
                // in place (see applyLiveStyleUpdates), so they don't need a
                // re-render (which would flash the pin).
                self.applyLiveStyleUpdates(from: obj, to: marker)
                // Icon fields (url / size / anchor) re-render the annotation so
                // viewFor reapplies the image and centerOffset; the fields above
                // mutate in place. See AppleMapMarker.applyIconUpdates.
                if marker.applyIconUpdates(from: obj) { toRefresh.append(marker) }
            }
            if !toRefresh.isEmpty {
                self.mapView.removeAnnotations(toRefresh)
                self.mapView.addAnnotations(toRefresh)
            }
        }
    }

    func enableClustering(minClusterSize: Int? = nil) {
        runOnMainSync {
            if let minSize = minClusterSize { self.clusterMinSize = max(1, minSize) }
            self.clusteringEnabled = true
            self.refreshAnnotations()
        }
    }

    func disableClustering() {
        runOnMainSync {
            guard self.clusteringEnabled else { return }
            self.clusteringEnabled = false
            self.refreshAnnotations()
        }
    }

    /// Re-add every annotation so `viewFor` reruns and the clustering identifier
    /// is applied or cleared. Must be called on the main thread.
    private func refreshAnnotations() {
        let all = Array(self.markers.values)
        self.mapView.removeAnnotations(all)
        self.mapView.addAnnotations(all)
    }

}
