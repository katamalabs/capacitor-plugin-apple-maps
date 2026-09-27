import Foundation
import MapKit
import UIKit
import Capacitor

// MARK: - Map: user tracking, buildings, camera boundary, marker selection
//
// Per-map controls behind the plugin bridge (see ControlsBridge.swift). Split out
// to keep CapacitorAppleMaps.swift within SwiftLint's length budget.

extension Map {

    // MARK: User tracking

    /// Follow the user's location (and optionally heading). A non-`none` mode turns
    /// the user-location dot on; the host app still needs location permission.
    func setUserTrackingMode(_ mode: String) {
        DispatchQueue.main.async {
            let tracking = Map.userTrackingMode(from: mode)
            if tracking != .none {
                self.mapView.showsUserLocation = true
            }
            self.mapView.setUserTrackingMode(tracking, animated: true)
        }
    }

    /// Maps a JS tracking-mode string to `MKUserTrackingMode`. Pure, so it can be
    /// unit-tested.
    static func userTrackingMode(from string: String) -> MKUserTrackingMode {
        switch string.lowercased() {
        case "follow": return .follow
        case "followwithheading": return .followWithHeading
        default: return .none
        }
    }

    /// Show or hide an `MKUserTrackingButton` (a recenter/follow control) pinned to
    /// the map's bottom-trailing corner.
    func setUserTrackingButton(_ visible: Bool) {
        DispatchQueue.main.async {
            if visible {
                guard self.userTrackingButton == nil else { return }
                let button = MKUserTrackingButton(mapView: self.mapView)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
                button.layer.cornerRadius = 6
                button.layer.masksToBounds = true
                self.mapView.addSubview(button)
                NSLayoutConstraint.activate([
                    button.trailingAnchor.constraint(equalTo: self.mapView.trailingAnchor, constant: -12),
                    button.bottomAnchor.constraint(equalTo: self.mapView.bottomAnchor, constant: -12)
                ])
                self.userTrackingButton = button
            } else {
                self.userTrackingButton?.removeFromSuperview()
                self.userTrackingButton = nil
            }
        }
    }

    // MARK: Buildings

    func setBuildings(_ enabled: Bool) {
        DispatchQueue.main.async { self.mapView.showsBuildings = enabled }
    }

    // MARK: Camera boundary

    /// Restrict panning so the camera center stays within `southwest`..`northeast`.
    /// Passing nil corners clears the restriction.
    func setCameraBoundary(southwest: CLLocationCoordinate2D?, northeast: CLLocationCoordinate2D?) {
        runOnMainSync {
            guard let southwest = southwest, let northeast = northeast else {
                self.mapView.setCameraBoundary(nil, animated: true)
                return
            }
            let rect = boundingMapRect(southwest: southwest, northeast: northeast)
            self.mapView.setCameraBoundary(MKMapView.CameraBoundary(mapRect: rect), animated: true)
        }
    }

    // MARK: Marker selection

    /// Open the info-window bubble for a marker programmatically. Returns false if
    /// no marker has that id. A marker with no title selects without a bubble.
    @discardableResult
    func selectMarker(_ markerId: String) -> Bool {
        runOnMainSync {
            guard let marker = self.markers[markerId] else { return false }
            if !(marker.title?.isEmpty ?? true) {
                self.showCallout(for: marker)
            }
            return true
        }
    }

    /// Close any open info-window bubble.
    func deselectMarker() {
        runOnMainSync { self.dismissCallout() }
    }
}
