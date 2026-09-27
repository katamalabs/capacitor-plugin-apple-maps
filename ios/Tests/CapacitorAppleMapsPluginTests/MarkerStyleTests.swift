import XCTest
import MapKit
import Capacitor
@testable import CapacitorAppleMapsPlugin

/// Parity additions: marker opacity/tint/z-order parsing and the `MKMapType`
/// string round-trip behind get/setMapType. Split from CapacitorAppleMapsTests to
/// keep that file's body within SwiftLint's length budget.
class MarkerStyleTests: XCTestCase {

    func testMakeMarkerParsesStyleFields() {
        let coordinate = ["lat": 1.0, "lng": 2.0] as JSObject
        let marker = Map.makeMarker(from: [
            "coordinate": coordinate,
            "opacity": 0.5,
            "zIndex": 7.0,
            "tintColor": ["r": 255.0, "g": 0.0, "b": 0.0, "a": 255.0] as JSObject
        ])
        XCTAssertEqual(marker?.opacity, 0.5)
        XCTAssertEqual(marker?.zIndex, 7.0)
        XCTAssertNotNil(marker?.tintColor)

        // Defaults when omitted: fully opaque, z 0, no tint.
        let plain = Map.makeMarker(from: ["coordinate": coordinate])
        XCTAssertEqual(plain?.opacity, 1)
        XCTAssertEqual(plain?.zIndex, 0)
        XCTAssertNil(plain?.tintColor)
    }

    func testParseTintColor() {
        // r/g/b are 0..255; alpha defaults to fully opaque when absent.
        let opaqueRed = AppleMapMarker.parseTintColor(["r": 255.0, "g": 0.0, "b": 0.0] as JSObject)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        opaqueRed?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1, accuracy: 0.01)
        XCTAssertEqual(green, 0, accuracy: 0.01)
        XCTAssertEqual(blue, 0, accuracy: 0.01)
        XCTAssertEqual(alpha, 1, accuracy: 0.01)

        // A half-alpha value is honoured.
        let half = AppleMapMarker.parseTintColor(["r": 0.0, "g": 0.0, "b": 0.0, "a": 128.0] as JSObject)
        half?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(alpha, 128.0 / 255.0, accuracy: 0.01)

        // Malformed (missing a channel) is ignored rather than half-applied.
        XCTAssertNil(AppleMapMarker.parseTintColor(["r": 255.0, "g": 0.0] as JSObject))
    }

    func testMapTypeStringRoundTrip() {
        let names = ["standard", "satellite", "hybrid", "satelliteFlyover", "hybridFlyover", "mutedStandard"]
        for name in names {
            XCTAssertEqual(Map.mapTypeString(from: Map.mapType(from: name)), name)
        }
        // An unknown type string falls back to standard.
        XCTAssertEqual(Map.mapType(from: "bogus"), .standard)
    }

    func testUserTrackingModeMapping() {
        XCTAssertEqual(Map.userTrackingMode(from: "follow"), .follow)
        XCTAssertEqual(Map.userTrackingMode(from: "followWithHeading"), .followWithHeading)
        XCTAssertEqual(Map.userTrackingMode(from: "none"), MKUserTrackingMode.none)
        // Unknown/absent falls back to no tracking.
        XCTAssertEqual(Map.userTrackingMode(from: "bogus"), MKUserTrackingMode.none)
    }

    func testParseDashPattern() {
        XCTAssertEqual(Map.parseDashPattern([8.0, 4.0]), [NSNumber(value: 8.0), NSNumber(value: 4.0)])
        // Empty, non-array, and absent all mean "solid line".
        XCTAssertNil(Map.parseDashPattern([]))
        XCTAssertNil(Map.parseDashPattern("dashed"))
        XCTAssertNil(Map.parseDashPattern(nil))
    }

    func testConfigParsesShowsBuildings() throws {
        let center = ["lat": 0.0, "lng": 0.0] as JSObject
        // Defaults to true (MapKit's default), and honours an explicit false.
        XCTAssertTrue(try AppleMapConfig(fromJSObject: ["center": center]).showsBuildings)
        XCTAssertFalse(try AppleMapConfig(fromJSObject: ["center": center, "showsBuildings": false]).showsBuildings)
    }
}
