import Foundation
import MapKit
import Capacitor
import WebKit

// MARK: - Native-view mounting and frame syncing
//
// Split out of CapacitorAppleMaps.swift / CapacitorAppleMapsPlugin.swift to keep
// those types within SwiftLint's length budget. This is the compositing glue
// that keeps the native MKMapView aligned with its bound web element, ported
// from `@capacitor/google-maps`.

extension Map {

    func updateRender(mapBounds: CGRect) {
        runOnMainSync {
            let newWidth = round(Double(mapBounds.width))
            let newHeight = round(Double(mapBounds.height))
            let widthEqual = round(Double(self.mapView.bounds.width)) == newWidth
            let heightEqual = round(Double(self.mapView.bounds.height)) == newHeight
            if !widthEqual || !heightEqual {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.mapView.frame.size.width = mapBounds.width
                self.mapView.frame.size.height = mapBounds.height
                CATransaction.commit()
            }
        }
    }

    func rebindTargetContainer(mapBounds: CGRect) {
        runOnMainSync {
            let refWidth = round(Double(mapBounds.width))
            let refHeight = round(Double(mapBounds.height))
            guard let target = self.getTargetContainer(refWidth: refWidth, refHeight: refHeight) else { return }
            self.targetView = target
            target.tag = Map.mapTag
            target.removeAllSubview()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.mapView.frame.size.width = mapBounds.width
            self.mapView.frame.size.height = mapBounds.height
            CATransaction.commit()
            target.addSubview(self.mapView)
        }
    }

    /// Re-mount the map into its current webview container using the map's own
    /// size. Called when the app returns to the foreground, after WebKit may
    /// have rebuilt the scroll-view hierarchy and detached the native map's
    /// touch handling. Keeps the existing mount if a container can't be found.
    func remountIntoContainer() {
        DispatchQueue.main.async {
            let width = round(Double(self.mapView.bounds.width))
            let height = round(Double(self.mapView.bounds.height))
            guard width > 0, height > 0 else { return }

            // Clear the previous tag so getTargetContainer rediscovers from a
            // clean slate (its default reference tag is Map.mapTag).
            let previous = self.targetView
            previous?.tag = 0
            self.targetView = nil

            guard let target = self.getTargetContainer(refWidth: width, refHeight: height) else {
                // Couldn't rediscover a container; restore the previous mount.
                previous?.tag = Map.mapTag
                self.targetView = previous
                return
            }

            self.targetView = target
            target.tag = Map.mapTag
            target.removeAllSubview()
            self.mapView.frame = target.bounds
            target.addSubview(self.mapView)
        }
    }

    /// Finds the WKWebView child scroll view whose content size matches the bound
    /// element, so the native map can be mounted into it. Ported from
    /// `@capacitor/google-maps`. Must be called on the main thread.
    func getTargetContainer(refWidth: Double, refHeight: Double) -> UIView? {
        guard let webView = self.delegate?.bridge?.webView else { return nil }
        for item in webView.getAllSubViews() {
            guard let scrollView = item as? UIScrollView else { continue }
            let childScrollClass = NSClassFromString("WKChildScrollView")
            let scrollClass = NSClassFromString("WKScrollView")
            let isChildScroll = (childScrollClass.map { item.isKind(of: $0) } ?? false)
                || (scrollClass.map { item.isKind(of: $0) } ?? false)
            let isBridgeScroll = item.isEqual(webView.scrollView)
            if isChildScroll && !isBridgeScroll {
                scrollView.isScrollEnabled = true
                let height = Double(scrollView.contentSize.height)
                let width = Double(scrollView.contentSize.width)
                // The element carries an inner 200%-tall spacer, so the child
                // scroll view's contentSize is ~2x the element's size. Match with
                // a 1pt tolerance rather than an exact / floor-ceil-to-integer
                // check: on devices whose layout lands the element on a
                // half-point (e.g. iPhone 17 Pro at 558.5pt) contentSize.height/2
                // equals the element height exactly (1117/2 == 558.5), but the
                // old integer floor(558.5)=558 / ceil=559 comparison missed it,
                // leaving the map unmounted. Older devices happened to land on
                // whole points, which is why the exact check worked there.
                let widthEqual = abs(width - refWidth) <= 1.0
                let heightEqual = abs(height / 2.0 - refHeight) <= 1.0
                if widthEqual && heightEqual && item.tag < (self.targetView?.tag ?? Map.mapTag) {
                    return item
                }
            }
        }
        return nil
    }
}

// MARK: - Plugin frame-sync bridge

extension CapacitorAppleMapsPlugin {

    @objc func onResize(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let boundsObj = call.getObject("mapBounds") else {
            call.reject("mapBounds is required", PluginError.invalidArgument)
            return
        }
        map.updateRender(mapBounds: CGRect.fromJSObject(boundsObj))
        call.resolve()
    }

    @objc func onDisplay(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let map = maps[id] else {
            call.reject("map not found", PluginError.mapNotFound)
            return
        }
        guard let boundsObj = call.getObject("mapBounds") else {
            call.reject("mapBounds is required", PluginError.invalidArgument)
            return
        }
        map.rebindTargetContainer(mapBounds: CGRect.fromJSObject(boundsObj))
        call.resolve()
    }

    @objc func onScroll(_ call: CAPPluginCall) {
        // The native map is a subview inside the webview's own scroll view on
        // iOS, so it tracks page scrolling automatically. Nothing to do.
        call.resolve()
    }
}
