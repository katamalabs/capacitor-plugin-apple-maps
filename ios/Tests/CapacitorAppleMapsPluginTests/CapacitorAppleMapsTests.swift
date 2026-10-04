import XCTest
import MapKit
import Capacitor
@testable import CapacitorAppleMapsPlugin

class CapacitorAppleMapsTests: XCTestCase {

    // MARK: - Zoom <-> region conversion

    /// The zoom <-> longitude-delta conversion should round-trip for a fixed
    /// viewport width across the useful zoom range.
    func testZoomRoundTrip() {
        let width = 390.0 // typical iPhone point width
        for zoom in stride(from: 3.0, through: 18.0, by: 1.0) {
            let delta = zoomToLongitudeDelta(zoom, widthPoints: width)
            let recovered = longitudeDeltaToZoom(delta, widthPoints: width)
            XCTAssertEqual(zoom, recovered, accuracy: 0.0001, "zoom \(zoom) did not round-trip")
        }
    }

    /// A larger zoom must produce a narrower longitude span.
    func testHigherZoomIsNarrower() {
        let width = 390.0
        XCTAssertGreaterThan(
            zoomToLongitudeDelta(5, widthPoints: width),
            zoomToLongitudeDelta(12, widthPoints: width)
        )
    }

    /// A zero/invalid viewport width must fall back rather than divide by zero.
    func testZoomToDeltaHandlesZeroWidth() {
        let delta = zoomToLongitudeDelta(10, widthPoints: 0)
        XCTAssertTrue(delta.isFinite)
        XCTAssertGreaterThan(delta, 0)
    }

    /// A zero span must not produce a non-finite zoom.
    func testLongitudeDeltaToZoomHandlesZeroDelta() {
        let zoom = longitudeDeltaToZoom(0, widthPoints: 390)
        XCTAssertTrue(zoom.isFinite)
    }

    // MARK: - Zoom clamping (minZoom floor / maxZoom ceiling)

    func testClampZoomUnboundedIsIdentity() {
        XCTAssertEqual(clampZoom(11.0, minZoom: nil, maxZoom: nil), 11.0)
    }

    func testClampZoomAppliesFloorAndCeiling() {
        XCTAssertEqual(clampZoom(3.0, minZoom: 7.0, maxZoom: nil), 7.0)   // below floor
        XCTAssertEqual(clampZoom(20.0, minZoom: nil, maxZoom: 18.0), 18.0) // above ceiling
        XCTAssertEqual(clampZoom(12.0, minZoom: 7.0, maxZoom: 18.0), 12.0) // in range
    }

    /// An inverted range should not trap the value between crossed bounds; the
    /// ceiling wins (min is applied first, then max).
    func testClampZoomInvertedRangeCeilingWins() {
        XCTAssertEqual(clampZoom(12.0, minZoom: 18.0, maxZoom: 7.0), 7.0)
    }

    // MARK: - Marker payload parsing

    func testMakeMarkerReadsAllFields() {
        let obj: JSObject = [
            "coordinate": ["lat": 42.36, "lng": -71.06] as JSObject,
            "title": "Boston",
            "snippet": "MA",
            "iconUrl": "pin.png",
            "iconSize": ["width": 30.0, "height": 36.0] as JSObject
        ]
        let marker = Map.makeMarker(from: obj)
        XCTAssertNotNil(marker)
        XCTAssertEqual(marker?.coordinate.latitude ?? 0, 42.36, accuracy: 1e-9)
        XCTAssertEqual(marker?.title, "Boston")
        XCTAssertEqual(marker?.subtitle, "MA")
        XCTAssertEqual(marker?.iconUrl, "pin.png")
        XCTAssertEqual(marker?.iconSize, CGSize(width: 30, height: 36))
    }

    func testMakeMarkerUsesCustomIdButIgnoresEmpty() {
        let coordinate = ["lat": 0.0, "lng": 0.0] as JSObject
        let custom = Map.makeMarker(from: ["coordinate": coordinate, "markerId": "abc"])
        XCTAssertEqual(custom?.markerId, "abc")

        let empty = Map.makeMarker(from: ["coordinate": coordinate, "markerId": ""])
        XCTAssertFalse(empty?.markerId.isEmpty ?? true) // fell back to a generated id
        XCTAssertNotEqual(empty?.markerId, "")
    }

    func testMakeMarkerParsesDraggable() {
        let coordinate = ["lat": 1.0, "lng": 2.0] as JSObject
        XCTAssertTrue(Map.makeMarker(from: ["coordinate": coordinate, "draggable": true])?.isDraggable ?? false)
        // Defaults off when omitted, preserving the non-draggable behavior.
        XCTAssertFalse(Map.makeMarker(from: ["coordinate": coordinate])?.isDraggable ?? true)
    }

    func testMakeMarkerReturnsNilWithoutCoordinate() {
        XCTAssertNil(Map.makeMarker(from: ["title": "no coord"]))
        XCTAssertNil(Map.makeMarker(from: ["coordinate": ["lat": 1.0] as JSObject]))
    }

    // MARK: - Overlay style parsing

    func testOverlayStyleUnfilledUsesDefaults() {
        let style = Map.overlayStyle(from: [:], defaultLineWidth: 3, filled: false)
        XCTAssertEqual(style.lineWidth, 3)
        XCTAssertNil(style.fillColor) // polylines never fill
        XCTAssertNotNil(style.strokeColor) // defaults to system blue
    }

    func testOverlayStyleFilledParsesColorsAndWidth() {
        let obj: JSObject = [
            "strokeColor": "#FF0000",
            "strokeWeight": 5.0,
            "fillColor": "#00FF00",
            "fillOpacity": 0.5
        ]
        let style = Map.overlayStyle(from: obj, defaultLineWidth: 2, filled: true)
        XCTAssertEqual(style.lineWidth, 5)

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        style.strokeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1.0, accuracy: 1e-6)

        XCTAssertNotNil(style.fillColor)
        style.fillColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(green, 1.0, accuracy: 1e-6)
        XCTAssertEqual(alpha, 0.5, accuracy: 1e-6)
    }

    // MARK: - CAPPluginCall string-array reading (diagnostic)

    /// Reproduces exactly how the bridge builds a call's options, to determine
    /// whether `getArray` can read a JS string array (as removeMarkers /
    /// removeOverlays need).
    func testGetArrayReadsStringArrayFromCoercedOptions() {
        let options = JSTypes.coerceDictionaryToJSObject(["id": "map", "ids": ["a", "b", "c"]]) ?? [:]
        guard let call = CAPPluginCall(
            callbackId: "t", methodName: "removeOverlays",
            options: options, success: { _, _ in }, error: { _ in }
        ) else {
            XCTFail("could not construct CAPPluginCall")
            return
        }
        let raw = call.getArray("ids")
        XCTAssertNotNil(raw, "getArray returned nil for a string array")
        XCTAssertEqual(raw?.compactMap { $0 as? String }, ["a", "b", "c"])
        XCTAssertNotNil(call.getArray("ids") as? [String], "whole-array cast returned nil")
    }

    // MARK: - Config parsing

    func testConfigParsesCenterAndZoom() throws {
        let obj: JSObject = [
            "center": ["lat": 42.36, "lng": -71.06] as JSObject,
            "zoom": 11.0,
            "minZoom": 7.0
        ]
        let config = try AppleMapConfig(fromJSObject: obj)
        XCTAssertEqual(config.center.latitude, 42.36, accuracy: 1e-9)
        XCTAssertEqual(config.center.longitude, -71.06, accuracy: 1e-9)
        XCTAssertEqual(config.zoom, 11.0)
        XCTAssertEqual(config.minZoom, 7.0)
    }

    func testConfigDefaultsZoomWhenMissing() throws {
        let obj: JSObject = ["center": ["lat": 0.0, "lng": 0.0] as JSObject]
        let config = try AppleMapConfig(fromJSObject: obj)
        XCTAssertEqual(config.zoom, 12.0)
        XCTAssertNil(config.minZoom)
    }

    func testConfigThrowsWithoutCenter() {
        let obj: JSObject = ["zoom": 11.0]
        XCTAssertThrowsError(try AppleMapConfig(fromJSObject: obj))
    }

    func testConfigParsesMaxZoomAndMapType() throws {
        let obj: JSObject = [
            "center": ["lat": 0.0, "lng": 0.0] as JSObject,
            "maxZoom": 18.0,
            "mapType": "hybrid"
        ]
        let config = try AppleMapConfig(fromJSObject: obj)
        XCTAssertEqual(config.maxZoom, 18.0)
        XCTAssertEqual(config.mapType, "hybrid")
    }

    func testConfigDefaultsMapTypeToStandard() throws {
        let obj: JSObject = ["center": ["lat": 0.0, "lng": 0.0] as JSObject]
        let config = try AppleMapConfig(fromJSObject: obj)
        XCTAssertNil(config.maxZoom)
        XCTAssertEqual(config.mapType, "standard")
    }

    func testConfigParsesShowInfoWindows() throws {
        let center = ["lat": 0.0, "lng": 0.0] as JSObject
        let enabled = try AppleMapConfig(fromJSObject: ["center": center, "showInfoWindows": true])
        XCTAssertTrue(enabled.showInfoWindows)
        // Defaults off, preserving the original tap-only behavior.
        let disabled = try AppleMapConfig(fromJSObject: ["center": center])
        XCTAssertFalse(disabled.showInfoWindows)
    }

    /// Parse the config through the SAME coercion the bridge applies to a JS
    /// object (not a Swift literal), to catch a boolean that survives a literal
    /// but not the real `create` path.
    func testConfigParsesShowInfoWindowsThroughBridgeCoercion() throws {
        let coerced = JSTypes.coerceDictionaryToJSObject([
            "center": ["lat": 1.0, "lng": 2.0],
            "showInfoWindows": true
        ]) ?? [:]
        let config = try AppleMapConfig(fromJSObject: coerced)
        XCTAssertTrue(config.showInfoWindows)
    }

    // MARK: - Map type mapping

    func testMapTypeMappingIsCaseInsensitive() {
        XCTAssertEqual(Map.mapType(from: "satellite"), .satellite)
        XCTAssertEqual(Map.mapType(from: "Hybrid"), .hybrid)
        XCTAssertEqual(Map.mapType(from: "satelliteFlyover"), .satelliteFlyover)
        XCTAssertEqual(Map.mapType(from: "hybridflyover"), .hybridFlyover)
        XCTAssertEqual(Map.mapType(from: "mutedStandard"), .mutedStandard)
    }

    func testMapTypeUnknownFallsBackToStandard() {
        XCTAssertEqual(Map.mapType(from: "standard"), .standard)
        XCTAssertEqual(Map.mapType(from: "nonsense"), .standard)
    }

    // MARK: - Overlay coordinate parsing

    func testParseCoordsReadsLatLngObjects() {
        let arr: [JSObject] = [["lat": 1.0, "lng": 2.0], ["lat": 3.0, "lng": 4.0]]
        let coords = Map.parseCoords(arr)
        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude, 1.0, accuracy: 1e-9)
        XCTAssertEqual(coords[1].longitude, 4.0, accuracy: 1e-9)
    }

    func testParseCoordsIgnoresMalformedEntriesAndNonArrays() {
        let mixed: [JSObject] = [["lat": 1.0, "lng": 2.0], ["lat": 3.0]]
        XCTAssertEqual(Map.parseCoords(mixed).count, 1)
        XCTAssertEqual(Map.parseCoords(nil).count, 0)
        XCTAssertEqual(Map.parseCoords("not an array").count, 0)
    }

    /// A flat ring of coordinates yields a single exterior ring.
    func testParseRingsSingleRing() {
        let ring: [JSObject] = [
            ["lat": 0.0, "lng": 0.0], ["lat": 0.0, "lng": 1.0], ["lat": 1.0, "lng": 1.0]
        ]
        let rings = Map.parseRings(ring)
        XCTAssertEqual(rings.count, 1)
        XCTAssertEqual(rings[0].count, 3)
    }

    /// An array of rings yields exterior + holes in order.
    func testParseRingsMultipleRings() {
        let exterior: [JSObject] = [
            ["lat": 0.0, "lng": 0.0], ["lat": 0.0, "lng": 4.0], ["lat": 4.0, "lng": 4.0]
        ]
        let hole: [JSObject] = [
            ["lat": 1.0, "lng": 1.0], ["lat": 1.0, "lng": 2.0], ["lat": 2.0, "lng": 2.0]
        ]
        let rings = Map.parseRings([exterior, hole])
        XCTAssertEqual(rings.count, 2)
        XCTAssertEqual(rings[0].count, 3)
        XCTAssertEqual(rings[1].count, 3)
    }

    // MARK: - Hex color parsing

    func testColorParsesSixDigitHex() {
        let color = Map.color("#FF0000", opacity: nil)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertNotNil(color)
        color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1.0, accuracy: 1e-6)
        XCTAssertEqual(green, 0.0, accuracy: 1e-6)
        XCTAssertEqual(blue, 0.0, accuracy: 1e-6)
        XCTAssertEqual(alpha, 1.0, accuracy: 1e-6)
    }

    func testColorParsesEightDigitHexAlpha() {
        let color = Map.color("#0000FF80", opacity: nil)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(blue, 1.0, accuracy: 1e-6)
        XCTAssertEqual(alpha, 128.0 / 255.0, accuracy: 1e-6)
    }

    /// An explicit opacity overrides any alpha baked into the hex string.
    func testColorOpacityOverridesHexAlpha() {
        let color = Map.color("#0000FF80", opacity: 0.5)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(alpha, 0.5, accuracy: 1e-6)
    }

    func testColorReturnsNilForMalformedInput() {
        XCTAssertNil(Map.color(nil, opacity: nil))
        XCTAssertNil(Map.color("not-a-color", opacity: nil))
        XCTAssertNil(Map.color("#FFFF", opacity: nil)) // unsupported length
    }

    // MARK: - CGRect parsing

    func testCGRectFromJSObject() {
        let obj: JSObject = ["x": 1.0, "y": 2.0, "width": 3.0, "height": 4.0]
        let rect = CGRect.fromJSObject(obj)
        XCTAssertEqual(rect.origin.x, 1.0)
        XCTAssertEqual(rect.origin.y, 2.0)
        XCTAssertEqual(rect.size.width, 3.0)
        XCTAssertEqual(rect.size.height, 4.0)
    }

    func testCGRectFromJSObjectDefaultsToZero() {
        let rect = CGRect.fromJSObject([:])
        XCTAssertEqual(rect, .zero)
    }

    // MARK: - Search distance filter

    func testWithinDistanceNoFilterWhenLimitMissing() {
        let boston = CLLocation(latitude: 42.36, longitude: -71.06)
        let saoPaulo = CLLocationCoordinate2D(latitude: -23.55, longitude: -46.63)
        // No/zero limit means "keep everything".
        XCTAssertTrue(withinDistance(maxKm: nil, from: boston, to: saoPaulo))
        XCTAssertTrue(withinDistance(maxKm: 0, from: boston, to: saoPaulo))
        // No center means "keep everything".
        XCTAssertTrue(withinDistance(maxKm: 800, from: nil, to: saoPaulo))
    }

    // MARK: - Search failures

    func testSearchFailureResolvesNoErrorAndNoMatches() {
        XCTAssertNil(searchFailure(nil))
        XCTAssertNil(searchFailure(MKError(.placemarkNotFound)))
    }

    func testSearchFailureRejectsEverythingElse() {
        XCTAssertNotNil(searchFailure(MKError(.loadingThrottled)))
        XCTAssertNotNil(searchFailure(MKError(.serverFailure)))
        XCTAssertNotNil(searchFailure(URLError(.notConnectedToInternet)))
    }

    // MARK: - Search resolve payload

    func testResolvePayloadCarriesThePlaceSpan() {
        // Quebec the province, as MapKit bounds it.
        let payload = resolvePayload(
            coordinate: CLLocationCoordinate2D(latitude: 52.94, longitude: -73.55),
            title: "Quebec",
            span: MKCoordinateSpan(latitudeDelta: 18.28, longitudeDelta: 23.4)
        )
        XCTAssertEqual(payload["lat"] as? Double, 52.94)
        XCTAssertEqual(payload["lng"] as? Double, -73.55)
        XCTAssertEqual(payload["title"] as? String, "Quebec")
        XCTAssertEqual(payload["latitudeDelta"] as? Double, 18.28)
        XCTAssertEqual(payload["longitudeDelta"] as? Double, 23.4)
    }

    func testResolvePayloadOmitsAMissingOrEmptySpan() {
        let here = CLLocationCoordinate2D(latitude: 42.36, longitude: -71.06)
        for span in [nil, MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)] {
            let payload = resolvePayload(coordinate: here, title: "Boston", span: span)
            XCTAssertNil(payload["latitudeDelta"])
            XCTAssertNil(payload["longitudeDelta"])
            XCTAssertEqual(payload["title"] as? String, "Boston")
        }
    }

    func testWithinDistanceKeepsNearbyDropsFar() {
        let boston = CLLocation(latitude: 42.36, longitude: -71.06)
        let portland = CLLocationCoordinate2D(latitude: 43.66, longitude: -70.26) // ~150 km
        let saoPaulo = CLLocationCoordinate2D(latitude: -23.55, longitude: -46.63) // ~7000 km
        XCTAssertTrue(withinDistance(maxKm: 800, from: boston, to: portland))
        XCTAssertFalse(withinDistance(maxKm: 800, from: boston, to: saoPaulo))
    }
}

// MARK: - Appearance toggles (#8)
//
// In an extension so the primary test-class body stays within SwiftLint's
// type_body_length budget.
extension CapacitorAppleMapsTests {

    // MARK: Color scheme mapping (dark-mode override)

    func testUserInterfaceStyleMapping() {
        XCTAssertEqual(Map.userInterfaceStyle(from: "light"), .light)
        XCTAssertEqual(Map.userInterfaceStyle(from: "Dark"), .dark)
    }

    func testUserInterfaceStyleDefaultsToUnspecified() {
        XCTAssertEqual(Map.userInterfaceStyle(from: "default"), .unspecified)
        XCTAssertEqual(Map.userInterfaceStyle(from: "nonsense"), .unspecified)
    }

    // MARK: Appearance config parsing

    func testConfigParsesAppearanceToggles() throws {
        let obj: JSObject = [
            "center": ["lat": 0.0, "lng": 0.0] as JSObject,
            "showsTraffic": true,
            "showsPointsOfInterest": false,
            "showsCompass": false,
            "showsScale": true,
            "colorScheme": "dark"
        ]
        let config = try AppleMapConfig(fromJSObject: obj)
        XCTAssertTrue(config.showsTraffic)
        XCTAssertFalse(config.showsPointsOfInterest)
        XCTAssertFalse(config.showsCompass)
        XCTAssertTrue(config.showsScale)
        XCTAssertEqual(config.colorScheme, "dark")
    }

    /// The defaults mirror MapKit's own: traffic/scale off, POI/compass on,
    /// system color scheme.
    func testConfigAppearanceDefaults() throws {
        let config = try AppleMapConfig(fromJSObject: ["center": ["lat": 0.0, "lng": 0.0] as JSObject])
        XCTAssertFalse(config.showsTraffic)
        XCTAssertTrue(config.showsPointsOfInterest)
        XCTAssertTrue(config.showsCompass)
        XCTAssertFalse(config.showsScale)
        XCTAssertEqual(config.colorScheme, "default")
    }

    // MARK: Gestures + padding (#10)

    func testConfigParsesGestures() throws {
        let obj: JSObject = [
            "center": ["lat": 0.0, "lng": 0.0] as JSObject,
            "gestures": ["scroll": false, "zoom": false, "rotate": true, "pitch": false] as JSObject
        ]
        let config = try AppleMapConfig(fromJSObject: obj)
        XCTAssertFalse(config.scrollEnabled)
        XCTAssertFalse(config.zoomEnabled)
        XCTAssertTrue(config.rotateEnabled)
        XCTAssertFalse(config.pitchEnabled)
    }

    /// Gestures all default on; an omitted gesture key keeps that gesture enabled.
    func testConfigGestureDefaults() throws {
        let config = try AppleMapConfig(fromJSObject: ["center": ["lat": 0.0, "lng": 0.0] as JSObject])
        XCTAssertTrue(config.scrollEnabled)
        XCTAssertTrue(config.zoomEnabled)
        XCTAssertTrue(config.rotateEnabled)
        XCTAssertTrue(config.pitchEnabled)
    }

    func testParsePaddingReadsSidesAndDefaultsToZero() {
        let insets = AppleMapConfig.parsePadding(["top": 10.0, "left": 20.0, "bottom": 30.0] as JSObject)
        XCTAssertEqual(insets.top, 10, accuracy: 1e-6)
        XCTAssertEqual(insets.left, 20, accuracy: 1e-6)
        XCTAssertEqual(insets.bottom, 30, accuracy: 1e-6)
        XCTAssertEqual(insets.right, 0, accuracy: 1e-6) // omitted side defaults to 0
        XCTAssertEqual(AppleMapConfig.parsePadding(nil), .zero)
        XCTAssertEqual(AppleMapConfig.parsePadding("not an object"), .zero)
    }

    // MARK: - Autocomplete result types

    /// No option at all keeps the behaviour every existing caller relies on.
    func testResultTypesDefaultWhenOmitted() {
        XCTAssertEqual(parseCompleterResultTypes(nil), [.address, .pointOfInterest])
    }

    /// A "where" field asks for addresses alone and must not get landmarks back.
    func testResultTypesAddressOnly() {
        XCTAssertEqual(parseCompleterResultTypes(["address"]), [.address])
    }

    func testResultTypesCombine() {
        XCTAssertEqual(parseCompleterResultTypes(["pointOfInterest", "query"]), [.pointOfInterest, .query])
    }

    /// An empty option set makes the completer return nothing, which looks like
    /// a broken search - so nothing usable means the default, not silence.
    func testResultTypesFallBackWhenNothingUsable() {
        XCTAssertEqual(parseCompleterResultTypes([]), defaultCompleterResultTypes)
        XCTAssertEqual(parseCompleterResultTypes(["landmark"]), defaultCompleterResultTypes)
    }

    func testResultTypesIgnoreUnknownNames() {
        XCTAssertEqual(parseCompleterResultTypes(["address", "landmark"]), [.address])
    }
}
