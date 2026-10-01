import Foundation
import MapKit
import UIKit
import Capacitor

// MARK: - Marker icon resolution
//
// Split out of CapacitorAppleMaps.swift to keep the core Map type within
// SwiftLint's length budget. Resolves a marker's `iconUrl` (bundled asset,
// `data:` URI, or `http(s):` download) to a sized image, caching results in the
// Map's `NSCache` and de-duping in-flight downloads.

extension Map {

    /// Resolves a marker icon. Returns nil synchronously for `http(s):` URLs and
    /// sets the image on the live annotation view once the download finishes.
    /// Must be called on the main thread.
    func annotationImage(for marker: AppleMapMarker, in mapView: MKMapView) -> UIImage? {
        guard let iconUrl = marker.iconUrl else { return nil }

        if let cached = iconCache.object(forKey: iconUrl as NSString) {
            return resize(cached, marker.iconSize)
        }

        if iconUrl.hasPrefix("data:") {
            if let commaIndex = iconUrl.firstIndex(of: ","),
               let data = Data(base64Encoded: String(iconUrl[iconUrl.index(after: commaIndex)...])),
               let image = UIImage(data: data) {
                iconCache.setObject(image, forKey: iconUrl as NSString)
                return resize(image, marker.iconSize)
            }
            return nil
        }

        if iconUrl.hasPrefix("http") {
            downloadRemoteIcon(iconUrl, in: mapView)
            return nil
        }

        // Bundled web asset - Capacitor copies the web `static/` dir into the app
        // bundle under `public/`.
        if let image = UIImage(named: "public/\(iconUrl)") {
            iconCache.setObject(image, forKey: iconUrl as NSString)
            return resize(image, marker.iconSize)
        }
        return nil
    }

    /// Fetches a remote icon once and applies it to every live annotation view
    /// using it. De-dupes concurrent requests for the same url and remembers
    /// permanent misses so a re-render doesn't re-download. Must be called on the
    /// main thread; the completion hops back to it.
    private func downloadRemoteIcon(_ iconUrl: String, in mapView: MKMapView) {
        guard !failedIconURLs.contains(iconUrl), !inFlightIconURLs.contains(iconUrl) else { return }
        guard let url = URL(string: iconUrl) else {
            failedIconURLs.insert(iconUrl)
            return
        }
        inFlightIconURLs.insert(iconUrl)
        URLSession.shared.dataTask(with: url) { [weak self, weak mapView] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlightIconURLs.remove(iconUrl)

                guard let data = data, let image = UIImage(data: data) else {
                    // A response with no usable image (404 body, wrong content,
                    // decode failure) is a permanent miss; a transport error
                    // (offline, timeout) is left out so a later render can retry.
                    if error == nil { self.failedIconURLs.insert(iconUrl) }
                    return
                }

                self.iconCache.setObject(image, forKey: iconUrl as NSString)
                guard let mapView = mapView else { return }
                for marker in self.markersAwaitingIcon(iconUrl) {
                    guard let view = mapView.view(for: marker) else { continue }
                    let sized = self.resize(image, marker.iconSize)
                    view.image = sized
                    if let sized = sized {
                        view.centerOffset = marker.centerOffset(for: sized.size)
                    }
                }
            }
        }.resume()
    }

    /// Markers that should receive a just-downloaded `iconUrl`. Every live marker
    /// currently using the url, not only the one whose render started the download
    /// (later requests for the same url were de-duped away and are waiting too).
    /// A marker whose icon changed or that was removed mid-download is excluded,
    /// so a stale download can't overwrite a newer icon.
    func markersAwaitingIcon(_ iconUrl: String) -> [AppleMapMarker] {
        markers.values.filter { $0.iconUrl == iconUrl }
    }

    private func resize(_ image: UIImage, _ size: CGSize?) -> UIImage? {
        guard let size = size else { return image }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
