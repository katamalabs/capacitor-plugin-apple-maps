import Foundation
import MapKit
import Capacitor

/// The `MKLaunchOptionsDirectionsModeKey` value for a JS `transportType`. Mirrors
/// `parseTransportType` (Directions.swift) but returns the launch-option string
/// the Maps app expects; driving is the default, matching an omitted mode.
func launchDirectionsMode(_ name: String?) -> String {
    switch name {
    case "walking": return MKLaunchOptionsDirectionsModeWalking
    case "transit": return MKLaunchOptionsDirectionsModeTransit
    default: return MKLaunchOptionsDirectionsModeDriving
    }
}

/// Hands off a place, or directions to it, to the system Maps app via
/// `MKMapItem.openMaps`. Keyless and map-independent, like `DirectionsService`:
/// it leaves the host app rather than touching any map view, and resolves once
/// the launch is requested (it does not wait for Maps to appear).
class MapsLaunchService {
    func open(_ call: CAPPluginCall) {
        guard let destinationObj = call.getObject("destination"),
              let destinationCoord = parseLatLng(destinationObj["coordinate"] as? JSObject) else {
            call.reject("destination with a coordinate { lat, lng } is required", PluginError.invalidArgument)
            return
        }
        let destinationName = destinationObj["name"] as? String
        let directions = call.getObject("directions")
        let showsTraffic = call.getBool("showsTraffic", false)
        let mapTypeString = call.getString("mapType")

        DispatchQueue.main.async {
            let destination = MapsLaunchService.mapItem(coordinate: destinationCoord, name: destinationName)

            var launchOptions: [String: Any] = [MKLaunchOptionsShowsTrafficKey: showsTraffic]
            if let mapTypeString = mapTypeString {
                launchOptions[MKLaunchOptionsMapTypeKey] = NSNumber(value: Map.mapType(from: mapTypeString).rawValue)
            }

            let items: [MKMapItem]
            if let directions = directions {
                // Directions: [origin, destination]. An omitted or malformed origin
                // routes from the device's current location; the Maps app asks for
                // its own location permission, so this plugin's does not gate it.
                let origin: MKMapItem
                if let originObj = directions["origin"] as? JSObject,
                   let originCoord = parseLatLng(originObj["coordinate"] as? JSObject) {
                    origin = MapsLaunchService.mapItem(coordinate: originCoord, name: originObj["name"] as? String)
                } else {
                    origin = MKMapItem.forCurrentLocation()
                }
                items = [origin, destination]
                launchOptions[MKLaunchOptionsDirectionsModeKey] =
                    launchDirectionsMode(directions["transportType"] as? String)
            } else {
                items = [destination]
            }

            MKMapItem.openMaps(with: items, launchOptions: launchOptions)
            call.resolve()
        }
    }

    /// An `MKMapItem` at `coordinate`, labelled `name` when a non-empty one is
    /// given so the Maps app shows it on the pin instead of the raw coordinate.
    private static func mapItem(coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        if let name = name, !name.isEmpty {
            item.name = name
        }
        return item
    }
}
