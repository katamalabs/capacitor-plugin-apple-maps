import Foundation
import MapKit
import Capacitor

/// Reads a `{ lat, lng }` object into a coordinate. Nil when either field is
/// missing, so a malformed origin/destination is rejected rather than routed
/// from `(0, 0)` in the Gulf of Guinea.
func parseLatLng(_ object: JSObject?) -> CLLocationCoordinate2D? {
    guard let object = object,
          let lat = object["lat"] as? Double,
          let lng = object["lng"] as? Double else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

/// Reads a JS epoch-milliseconds timestamp into a `Date`. Nil when absent, so an
/// omitted departure/arrival leaves the request on MapKit's default ("now").
/// Non-positive values are treated as absent rather than 1970.
func parseEpochDate(_ millis: Double?) -> Date? {
    guard let millis = millis, millis > 0 else { return nil }
    return Date(timeIntervalSince1970: millis / 1000)
}

/// Maps the JS `transportType` string to MapKit's option. Unknown or omitted
/// falls back to driving - the common case and what callers get by default.
func parseTransportType(_ name: String?) -> MKDirectionsTransportType {
    switch name {
    case "walking": return .walking
    case "transit": return .transit
    case "automobile", "driving", nil: return .automobile
    default: return .automobile
    }
}

/// The error a finished `MKDirections.calculate` should reject with, or nil when
/// it should resolve. "No route exists" arrives as `MKError.directionsNotFound`
/// (e.g. driving across an ocean) and is an answer - an empty route list - not a
/// failure. Anything else (offline, throttled via `loadingThrottled`, a server
/// error) is a failure: resolving it as `[]` would make "Apple could not answer"
/// indistinguishable from "there is genuinely no route".
func directionsFailure(_ error: Error?) -> Error? {
    guard let error = error else { return nil }
    if let mkError = error as? MKError, mkError.code == .directionsNotFound { return nil }
    return error
}

/// Decodes an `MKPolyline` into a `[{ lat, lng }]` path - the same shape
/// `addPolylines` accepts, so a caller can draw the returned route directly.
func polylineCoordinates(_ polyline: MKPolyline) -> [[String: Double]] {
    let count = polyline.pointCount
    guard count > 0 else { return [] }
    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
    return coords.map { ["lat": $0.latitude, "lng": $0.longitude] }
}

/// The JS payload for one `MKRoute`. `distance` is metres and
/// `expectedTravelTime` seconds (the ETA). `path` is the drawable geometry;
/// `steps` are the turn-by-turn instructions MapKit generated, with the trailing
/// empty-instruction step MapKit always appends dropped.
func routePayload(_ route: MKRoute) -> [String: Any] {
    var payload: [String: Any] = [
        "name": route.name,
        "distance": route.distance,
        "expectedTravelTime": route.expectedTravelTime,
        "path": polylineCoordinates(route.polyline)
    ]
    if !route.advisoryNotices.isEmpty {
        payload["advisoryNotices"] = route.advisoryNotices
    }
    let steps = route.steps.compactMap { step -> [String: Any]? in
        guard !step.instructions.isEmpty else { return nil }
        return ["instructions": step.instructions, "distance": step.distance]
    }
    if !steps.isEmpty {
        payload["steps"] = steps
    }
    return payload
}

/// Native directions via `MKDirections`. Data-only: it computes the route
/// geometry, distance and ETA and hands them back for the caller to draw (e.g.
/// with `addPolylines`); it does not touch any map view. Each call supersedes
/// the one before it, matching how `searchPlaces` cancels an in-flight search.
class DirectionsService {
    private var current: MKDirections?

    func route(_ call: CAPPluginCall) {
        guard let origin = parseLatLng(call.getObject("origin")) else {
            call.reject("origin with lat/lng is required", PluginError.invalidArgument)
            return
        }
        guard let destination = parseLatLng(call.getObject("destination")) else {
            call.reject("destination with lat/lng is required", PluginError.invalidArgument)
            return
        }
        let transportType = parseTransportType(call.getString("transportType"))
        let alternatives = call.getBool("alternatives", false)
        let departureDate = parseEpochDate(call.getDouble("departureDate"))
        let arrivalDate = parseEpochDate(call.getDouble("arrivalDate"))

        DispatchQueue.main.async {
            self.current?.cancel()

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = transportType
            request.requestsAlternateRoutes = alternatives
            // Set only when given, so an omitted date keeps MapKit's default ("now")
            // rather than pinning the ETA to the epoch. `expectedTravelTime` then
            // reflects predicted traffic for that departure/arrival time.
            if let departureDate = departureDate {
                request.departureDate = departureDate
            }
            if let arrivalDate = arrivalDate {
                request.arrivalDate = arrivalDate
            }

            // One MKDirections object serves one request; a fresh object per call
            // also avoids the loadingThrottled error that reusing one invites.
            let directions = MKDirections(request: request)
            self.current = directions
            directions.calculate { response, error in
                // A newer request cancelled this one; its caller has moved on.
                guard self.current === directions else {
                    call.resolve(["routes": []])
                    return
                }
                if let failure = directionsFailure(error) {
                    call.reject("Directions request failed: \(failure.localizedDescription)",
                                PluginError.operationFailed, failure)
                    return
                }
                let routes = (response?.routes ?? []).map { routePayload($0) }
                call.resolve(["routes": routes])
            }
        }
    }
}
