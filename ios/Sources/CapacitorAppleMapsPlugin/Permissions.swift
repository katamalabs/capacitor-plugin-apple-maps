import Foundation
import Capacitor
import CoreLocation

// MARK: - Location permission
//
// Implements the Capacitor permission pattern for the `location` alias, used by
// `enableCurrentLocation` (the blue user-location dot). The host app must still
// declare `NSLocationWhenInUseUsageDescription` in its Info.plist; without it the
// system prompt never appears, so `requestPermissions` rejects instead of waiting
// on an answer that will never come.

extension CapacitorAppleMapsPlugin: CLLocationManagerDelegate {

    /// The CLLocationManager, created on first use. Owning it (rather than a
    /// throwaway) is what lets the authorization-change delegate fire back into us.
    ///
    /// Must be called on the main thread. Core Location delivers delegate callbacks
    /// on the run loop of the thread that created the manager, and Capacitor's
    /// plugin queue has no run loop - a manager made there never calls back.
    func ensureLocationManager() -> CLLocationManager {
        if let manager = locationManager {
            return manager
        }
        let manager = CLLocationManager()
        manager.delegate = self
        locationManager = manager
        return manager
    }

    /// An authorization status mapped to a Capacitor `PermissionState` string.
    static func permissionState(for status: CLAuthorizationStatus) -> String {
        switch status {
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
        let status = runOnMainSync { ensureLocationManager().authorizationStatus }
        call.resolve(["location": Self.permissionState(for: status)])
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        runOnMainSync {
            let manager = ensureLocationManager()
            guard manager.authorizationStatus == .notDetermined else {
                // Already decided (granted, denied or restricted) - nothing to prompt.
                call.resolve(["location": Self.permissionState(for: manager.authorizationStatus)])
                return
            }
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
                call.reject("NSLocationWhenInUseUsageDescription is missing from Info.plist; "
                                + "iOS will not show the location prompt without it.",
                            PluginError.operationFailed)
                return
            }
            // The prompt is answered asynchronously; hold every caller (a second
            // request while the prompt is up must not displace the first) and
            // resolve them all from the delegate once the user responds.
            pendingPermissionCalls.append(call)
            manager.requestWhenInUseAuthorization()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resolvePendingPermissionCalls(with: manager.authorizationStatus)
    }

    /// Resolve every held `requestPermissions` call with `status`. A
    /// `.notDetermined` status is ignored: Core Location reports the initial status
    /// right after the manager is created, before the user has answered anything.
    /// Main thread only.
    func resolvePendingPermissionCalls(with status: CLAuthorizationStatus) {
        guard status != .notDetermined, !pendingPermissionCalls.isEmpty else { return }
        let calls = pendingPermissionCalls
        pendingPermissionCalls.removeAll()
        let state = Self.permissionState(for: status)
        for call in calls {
            call.resolve(["location": state])
        }
    }
}
