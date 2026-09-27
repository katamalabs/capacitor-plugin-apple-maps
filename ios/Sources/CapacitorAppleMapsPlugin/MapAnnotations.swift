import Foundation
import MapKit
import Capacitor
import UIKit

// MARK: - Map: camera + annotation views
//
// The per-map work behind the plugin's thin MKMapViewDelegate methods. Keeping it
// on `Map` (rather than in the bridge class) leaves CapacitorAppleMapsPlugin as a
// thin wrapper and keeps both types within SwiftLint's body-length budget.

extension Map {
    static let clusterReuseId = "appleMapCluster"
    static let markerReuseId = "appleMapMarker"
    // Markers with an icon and markers without one use different view classes
    // (MKAnnotationView vs MKMarkerAnnotationView) and so must not share a reuse
    // identifier — MapKit would hand back the wrong class from the reuse pool.
    static let markerDefaultReuseId = "appleMapMarkerDefault"

    /// Parse a JS camera config (`coordinate` / `zoom` / `animate`) and apply it.
    func setCamera(from configObj: JSObject) {
        var coordinate: CLLocationCoordinate2D?
        if let coordObj = configObj["coordinate"] as? JSObject,
           let lat = coordObj["lat"] as? Double,
           let lng = coordObj["lng"] as? Double {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        let zoom = configObj["zoom"] as? Double
        let animate = configObj["animate"] as? Bool ?? false
        setCameraInternal(coordinate: coordinate, zoom: zoom, animate: animate)
    }

    /// Build (or recycle) the annotation view for a marker, cluster, or the user
    /// location dot. Returns nil for the user location so MapKit draws its default.
    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

        if let cluster = annotation as? MKClusterAnnotation {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: Map.clusterReuseId) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: Map.clusterReuseId)
            view.annotation = cluster
            view.canShowCallout = false
            view.glyphText = "\(cluster.memberAnnotations.count)"
            view.markerTintColor = .systemGray
            view.displayPriority = .required
            return view
        }

        guard let marker = annotation as? AppleMapMarker else { return nil }

        // No icon → MapKit's native pin (MKMarkerAnnotationView), mirroring how
        // @capacitor/google-maps renders a default marker when the host supplies
        // none; a bare image-less MKAnnotationView would be invisible. The two
        // view classes can't share a reuse id.
        let hasIcon = !(marker.iconUrl?.isEmpty ?? true)
        let view: MKAnnotationView
        if hasIcon {
            view = mapView.dequeueReusableAnnotationView(withIdentifier: Map.markerReuseId)
                ?? MKAnnotationView(annotation: marker, reuseIdentifier: Map.markerReuseId)
        } else {
            view = mapView.dequeueReusableAnnotationView(withIdentifier: Map.markerDefaultReuseId) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: marker, reuseIdentifier: Map.markerDefaultReuseId)
        }
        view.annotation = marker
        view.clusteringIdentifier = clusteringEnabled ? Map.clusterReuseId : nil
        view.displayPriority = .required
        // Info windows are drawn as our own bubble (see Callout.swift), so the
        // native callout stays off. When info windows are on, hide the inline
        // title/subtitle labels too, so the bubble is the sole info display.
        if let markerView = view as? MKMarkerAnnotationView {
            let visibility: MKFeatureVisibility = config.showInfoWindows ? .hidden : .adaptive
            markerView.titleVisibility = visibility
            markerView.subtitleVisibility = visibility
        }

        // Reset first: a recycled image view must not keep a previous marker's
        // icon while an `https:` icon for this one is still downloading (the
        // async completion in `annotationImage` sets it on the live view).
        view.image = nil
        view.centerOffset = .zero
        if hasIcon, let image = annotationImage(for: marker, in: mapView) {
            view.image = image
            view.centerOffset = marker.centerOffset(for: image.size)
        }
        // The native callout stays off - we render our own bubble (Callout.swift),
        // because MapKit's callout doesn't show through the web-view compositing.
        view.canShowCallout = false
        return view
    }

    /// Clear MapKit's selection for a marker and show (or hide) our own info-window
    /// bubble. The pin stays its normal size rather than enlarging on selection.
    func handleMarkerSelection(_ marker: AppleMapMarker) {
        mapView.deselectAnnotation(marker, animated: false)
        if config.showInfoWindows && !(marker.title?.isEmpty ?? true) {
            showCallout(for: marker)
        } else {
            dismissCallout()
        }
    }

    /// Deselect a tapped cluster and zoom to frame its members.
    func expandCluster(_ cluster: MKClusterAnnotation, in mapView: MKMapView) {
        mapView.deselectAnnotation(cluster, animated: false)
        var rect = MKMapRect.null
        for member in cluster.memberAnnotations {
            let point = MKMapPoint(member.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0.01, height: 0.01))
        }
        let padding = UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }
}
