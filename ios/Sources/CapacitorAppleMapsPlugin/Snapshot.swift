import Foundation
import MapKit
import UIKit
import Capacitor

// MARK: - Map snapshot (#10)
//
// Renders the current map region to a PNG via MKMapSnapshotter, then composites
// the live annotation pins and overlays on top (MKMapSnapshotter itself renders
// only the base-map tiles, not the map view's subviews/overlays).

enum SnapshotError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

extension Map {
    /// Snapshot the visible region (with pins + overlays drawn in) and hand back a
    /// `data:image/png;base64,...` URL. `completion` is called on the main thread.
    func takeSnapshot(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.main.async {
            let options = MKMapSnapshotter.Options()
            options.region = self.mapView.region
            options.mapType = self.mapView.mapType
            options.size = self.mapView.bounds.size
            options.showsBuildings = true

            let snapshotter = MKMapSnapshotter(options: options)
            self.pendingSnapshotter = snapshotter
            // Composite on the main thread - it reads live annotation views.
            snapshotter.start(with: .main) { snapshot, error in
                self.pendingSnapshotter = nil
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let snapshot = snapshot else {
                    completion(.failure(SnapshotError.failed("snapshot produced no image")))
                    return
                }
                let composed = self.composite(snapshot)
                guard let data = composed.pngData() else {
                    completion(.failure(SnapshotError.failed("could not encode snapshot")))
                    return
                }
                completion(.success("data:image/png;base64," + data.base64EncodedString()))
            }
        }
    }

    /// Draw the base-map snapshot, then overlays, then pins on top.
    private func composite(_ snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            drawOverlays(into: context.cgContext, project: snapshot.point(for:))
            drawMarkers(into: context.cgContext, snapshot: snapshot)
        }
    }

    private func drawMarkers(into ctx: CGContext, snapshot: MKMapSnapshotter.Snapshot) {
        for marker in markers.values {
            // Render the live annotation view so the pin looks exactly as on the
            // map (default balloon or custom icon). MapKit positions a view so its
            // center sits at the coordinate offset by `centerOffset`.
            guard let view = mapView.view(for: marker) else { continue }
            let anchor = snapshot.point(for: marker.coordinate)
            let center = CGPoint(x: anchor.x + view.centerOffset.x, y: anchor.y + view.centerOffset.y)
            ctx.saveGState()
            ctx.translateBy(x: center.x - view.bounds.width / 2, y: center.y - view.bounds.height / 2)
            view.layer.render(in: ctx)
            ctx.restoreGState()
        }
    }

    /// Draw every overlay the way its renderer shows it on the live map: dash
    /// pattern, fill, and polygon holes included. `project` maps a coordinate to
    /// a point in `ctx` (the snapshot's `point(for:)`; a plain function in tests).
    func drawOverlays(into ctx: CGContext, project: (CLLocationCoordinate2D) -> CGPoint) {
        for overlay in overlays.values {
            let style = overlayStyles[ObjectIdentifier(overlay)]
            let path: CGPath
            var fill: CGColor?
            if let polyline = overlay as? MKPolyline {
                path = ringPath(polyline, project: project, closed: false)
            } else if let polygon = overlay as? MKPolygon {
                path = polygonPath(polygon, project: project)
                fill = style?.fillColor?.cgColor
            } else if let circle = overlay as? MKCircle {
                path = circlePath(circle, project: project)
                fill = style?.fillColor?.cgColor
            } else {
                continue
            }
            draw(path, into: ctx, style: style, fill: fill)
        }
    }

    private func draw(_ path: CGPath, into ctx: CGContext, style: OverlayStyle?, fill: CGColor?) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let fill = fill {
            // Even-odd so a polygon's interior rings come out as holes, as
            // MKPolygonRenderer draws them.
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath(using: .evenOdd)
        }
        ctx.addPath(path)
        ctx.setStrokeColor((style?.strokeColor ?? .systemBlue).cgColor)
        ctx.setLineWidth(style?.lineWidth ?? 3)
        ctx.setLineJoin(.round)
        if let dashes = style?.lineDashPattern, !dashes.isEmpty {
            ctx.setLineDash(phase: 0, lengths: dashes.map { CGFloat($0.doubleValue) })
        }
        ctx.strokePath()
    }

    /// The exterior ring plus one closed subpath per interior ring (hole).
    private func polygonPath(_ polygon: MKPolygon, project: (CLLocationCoordinate2D) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addPath(ringPath(polygon, project: project, closed: true))
        for hole in polygon.interiorPolygons ?? [] {
            path.addPath(ringPath(hole, project: project, closed: true))
        }
        return path
    }

    private func ringPath(_ shape: MKMultiPoint, project: (CLLocationCoordinate2D) -> CGPoint, closed: Bool) -> CGPath {
        let path = CGMutablePath()
        let points = shape.points()
        for index in 0..<shape.pointCount {
            let point = project(points[index].coordinate)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closed { path.closeSubpath() }
        return path
    }

    private func circlePath(_ circle: MKCircle, project: (CLLocationCoordinate2D) -> CGPoint) -> CGPath {
        let center = project(circle.coordinate)
        // Convert the radius (meters) to points via a coordinate one radius north.
        let north = CLLocationCoordinate2D(
            latitude: circle.coordinate.latitude + circle.radius / 111_320.0,
            longitude: circle.coordinate.longitude
        )
        let edge = project(north)
        let radius = hypot(edge.x - center.x, edge.y - center.y)
        return CGPath(
            ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
    }
}

extension CapacitorAppleMapsPlugin {
    @objc func takeSnapshot(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        map.takeSnapshot { result in
            switch result {
            case .success(let image):
                call.resolve(["image": image])
            case .failure(let error):
                call.reject(error.localizedDescription, PluginError.operationFailed, error)
            }
        }
    }
}
