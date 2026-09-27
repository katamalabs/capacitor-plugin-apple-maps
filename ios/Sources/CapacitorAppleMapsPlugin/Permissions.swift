import Foundation
import Capacitor
import CoreLocation

// MARK: - Location permission
//
// Implements the Capacitor permission pattern for the `location` alias, used by
// `enableCurrentLocation` (the blue user-location dot). The host app must still
// declare `NSLocationWhenInUseUsageDescription` in its Info.plist; without it the
// system prompt never appears and iOS treats access as denied.

extension CapacitorAppleMapsPlugin: CLLocationManagerDelegate {

    /// The CLLocationManager, created on first use. Owning it (rather than a
    /// throwaway) is what lets the authorization-change delegate fire back into us.
    func ensureLocationManager() -> CLLocationManager {
        if let manager = locationManager {
            return manager
        }
        let manager = CLLocationManager()
        manager.delegate = self
        locationManager = manager
        return manager
    }

    /// Current authorization mapped to a Capacitor `PermissionState` string.
    private func locationPermissionState() -> String {
        switch ensureLocationManager().authorizationStatus {
        case .notDetermined:
            return "prompt"
        case .restricted, .denied:
            return "denied"
        case .authorizedAlways, .authorizedWhenInUse:
            return "granted"
        @unknown default:
            return "prompt"
        }
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(["location": locationPermissionState()])
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        let manager = ensureLocationManager()
        if manager.authorizationStatus == .notDetermined {
            // The prompt is answered asynchronously; hold the call and resolve it
            // from the delegate once the user responds.
            bridge?.saveCall(call)
            permissionCallID = call.callbackId
            manager.requestWhenInUseAuthorization()
        } else {
            // Already decided (granted, denied or restricted) - nothing to prompt.
            checkPermissions(call)
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let callID = permissionCallID, let call = bridge?.getSavedCall(callID) else {
            return
        }
        checkPermissions(call)
        bridge?.releaseCall(call)
        permissionCallID = nil
    }
}
