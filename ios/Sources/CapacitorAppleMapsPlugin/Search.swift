import Foundation
import MapKit
import Capacitor

/// True when `coordinate` is within `maxKm` of `center`. A nil/zero limit or a
/// nil center means "no filter" (always true). Pure so it can be unit-tested.
func withinDistance(maxKm: Double?, from center: CLLocation?, to coordinate: CLLocationCoordinate2D) -> Bool {
    guard let maxKm = maxKm, maxKm > 0, let center = center else { return true }
    let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    return center.distance(from: here) / 1000.0 <= maxKm
}

/// Reads an optional `region` object into an `MKCoordinateRegion` and its center.
private func parseRegion(_ region: JSObject?) -> (region: MKCoordinateRegion, center: CLLocation)? {
    guard let region = region,
          let lat = region["latitude"] as? Double,
          let lng = region["longitude"] as? Double else { return nil }
    let latDelta = region["latitudeDelta"] as? Double ?? 1.0
    let lngDelta = region["longitudeDelta"] as? Double ?? 1.0
    let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    return (
        MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)),
        CLLocation(latitude: lat, longitude: lng)
    )
}

/// The error a finished `MKLocalSearch` should reject with, or nil when it should
/// resolve. "No matches" arrives as `MKError.placemarkNotFound`, and that is an
/// answer - an empty list - not a failure. Anything else (offline, throttled,
/// a server error) is a failure, and resolving it as `[]` would make "Apple did
/// not answer" indistinguishable from "there is nothing here".
func searchFailure(_ error: Error?) -> Error? {
    guard let error = error else { return nil }
    if let mkError = error as? MKError, mkError.code == .placemarkNotFound { return nil }
    return error
}

/// What `searchAutocomplete` returns when the caller does not say.
let defaultCompleterResultTypes: MKLocalSearchCompleter.ResultType = [.address, .pointOfInterest]

/// Reads the optional `resultTypes` string list into completer result types.
/// Unknown names are ignored, and a list that names nothing usable falls back
/// to the default: an empty option set would make the completer return no
/// suggestions at all, which reads as a broken search rather than a filter.
func parseCompleterResultTypes(_ names: [String]?) -> MKLocalSearchCompleter.ResultType {
    guard let names = names else { return defaultCompleterResultTypes }
    var types: MKLocalSearchCompleter.ResultType = []
    for name in names {
        switch name {
        case "address": types.insert(.address)
        case "pointOfInterest": types.insert(.pointOfInterest)
        case "query": types.insert(.query)
        default: break
        }
    }
    return types.isEmpty ? defaultCompleterResultTypes : types
}

/// The `searchResolve` payload. `span` is how much of the map the place covers -
/// a street address a few metres, a province hundreds of kilometres - which a
/// caller needs to tell "near this point" from "somewhere in this region". Left
/// out when the search gave no region for the place alone.
func resolvePayload(coordinate: CLLocationCoordinate2D, title: String, span: MKCoordinateSpan?) -> [String: Any] {
    var payload: [String: Any] = ["lat": coordinate.latitude, "lng": coordinate.longitude, "title": title]
    if let span = span, span.latitudeDelta > 0, span.longitudeDelta > 0 {
        payload["latitudeDelta"] = span.latitudeDelta
        payload["longitudeDelta"] = span.longitudeDelta
    }
    return payload
}

/// A "City, State" style secondary line, skipping the locality when it just
/// repeats the primary name.
private func placeSubtitle(for placemark: MKPlacemark, name: String?) -> String {
    var parts: [String] = []
    if let locality = placemark.locality, locality != name {
        parts.append(locality)
    }
    if let admin = placemark.administrativeArea {
        parts.append(admin)
    }
    if parts.isEmpty, let country = placemark.country {
        parts.append(country)
    }
    return parts.joined(separator: ", ")
}

/// Native place search. Offers two independent APIs:
///
/// - `autocomplete` / `resolve`: idiomatic type-ahead via `MKLocalSearchCompleter`,
///   returning lightweight `{id, title, subtitle}` completions that `resolve`
///   turns into coordinates on demand.
/// - `places`: a one-shot `MKLocalSearch` returning coordinate-bearing results,
///   optionally scoped to a region and filtered by distance.
///
/// Both kinds of id resolve through `resolve`.
class SearchService: NSObject, MKLocalSearchCompleterDelegate {
    // Autocomplete (MKLocalSearchCompleter)
    private var completer: MKLocalSearchCompleter?
    private var pendingCall: CAPPluginCall?
    private var completions: [String: MKLocalSearchCompletion] = [:]

    // One-shot search (MKLocalSearch)
    private var items: [String: MKMapItem] = [:]
    private var currentSearch: MKLocalSearch?

    // MARK: - Autocomplete (type-ahead)

    private func ensureCompleter() {
        if completer == nil {
            let newCompleter = MKLocalSearchCompleter()
            newCompleter.resultTypes = defaultCompleterResultTypes
            newCompleter.delegate = self
            completer = newCompleter
        }
    }

    func autocomplete(_ call: CAPPluginCall) {
        let query = call.getString("query") ?? ""
        let regionObj = call.getObject("region")
        let resultTypes = parseCompleterResultTypes(call.getArray("resultTypes") as? [String])
        DispatchQueue.main.async {
            self.pendingCall?.resolve(["results": []])

            if query.isEmpty {
                self.pendingCall = nil
                call.resolve(["results": []])
                return
            }

            self.ensureCompleter()
            guard let completer = self.completer else {
                call.resolve(["results": []])
                return
            }

            if let parsed = parseRegion(regionObj) {
                completer.region = parsed.region
            }
            // Set on every call, not only when given: the completer is shared, so
            // a call without the option must get the default back rather than
            // inherit the previous caller's filter.
            completer.resultTypes = resultTypes

            self.pendingCall = call
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard let call = pendingCall else { return }
        pendingCall = nil

        if completions.count > 300 {
            completions.removeAll()
        }

        var results: [[String: Any]] = []
        for completion in completer.results {
            let id = UUID().uuidString
            completions[id] = completion
            results.append([
                "id": id,
                "title": completion.title,
                "subtitle": completion.subtitle
            ])
        }
        call.resolve(["results": results])
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        pendingCall?.resolve(["results": []])
        pendingCall = nil
    }

    // MARK: - One-shot search (coordinate-bearing, filterable)

    func places(_ call: CAPPluginCall) {
        let query = call.getString("query") ?? ""
        if query.isEmpty {
            call.resolve(["results": []])
            return
        }

        let regionObj = call.getObject("region")
        let maxDistanceKm = call.getDouble("maxDistanceKm")
        let limit = call.getInt("limit")

        DispatchQueue.main.async {
            self.currentSearch?.cancel()

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query

            var center: CLLocation?
            if let parsed = parseRegion(regionObj) {
                request.region = parsed.region
                center = parsed.center
            }

            let search = MKLocalSearch(request: request)
            self.currentSearch = search
            search.start { response, error in
                // A newer search cancelled this one; its caller has moved on.
                guard self.currentSearch === search else {
                    call.resolve(["results": []])
                    return
                }
                if let failure = searchFailure(error) {
                    call.reject("Place search failed: \(failure.localizedDescription)", PluginError.operationFailed, failure)
                    return
                }
                if self.items.count > 300 {
                    self.items.removeAll()
                }

                var results: [[String: Any]] = []
                for item in response?.mapItems ?? [] {
                    let coordinate = item.placemark.coordinate
                    guard withinDistance(maxKm: maxDistanceKm, from: center, to: coordinate) else { continue }

                    let id = UUID().uuidString
                    self.items[id] = item
                    results.append([
                        "id": id,
                        "title": item.name ?? item.placemark.locality ?? "",
                        "subtitle": placeSubtitle(for: item.placemark, name: item.name),
                        "latitude": coordinate.latitude,
                        "longitude": coordinate.longitude
                    ])

                    if let limit = limit, limit > 0, results.count >= limit { break }
                }
                call.resolve(["results": results])
            }
        }
    }

    // MARK: - Resolve (either kind of id)

    func resolve(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.resolve([:])
            return
        }

        // A `places` result already carries its coordinate.
        if let item = items[id] {
            // No span: a `places` search's region bounds every result, not this one.
            call.resolve(resolvePayload(coordinate: item.placemark.coordinate, title: item.name ?? "", span: nil))
            return
        }

        // An `autocomplete` completion needs a search to get its coordinate.
        guard let completion = completions[id] else {
            call.resolve([:])
            return
        }
        DispatchQueue.main.async {
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            search.start { response, _ in
                guard let item = response?.mapItems.first else {
                    call.resolve([:])
                    return
                }
                // A completion search answers with the one place it names, so the
                // response's bounding region is that place's own extent.
                let span = response?.mapItems.count == 1 ? response?.boundingRegion.span : nil
                call.resolve(resolvePayload(coordinate: item.placemark.coordinate, title: item.name ?? completion.title, span: span))
            }
        }
    }
}
