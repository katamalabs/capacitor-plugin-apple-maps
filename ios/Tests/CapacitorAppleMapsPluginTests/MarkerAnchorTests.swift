import XCTest
import MapKit
import Capacitor
@testable import CapacitorAppleMapsPlugin

/// Icon anchoring: how a marker payload's `iconAnchor` is parsed and turned into
/// the `MKAnnotationView.centerOffset` that lands the anchor point on the
/// coordinate. Split from CapacitorAppleMapsTests to keep that file's body within
/// SwiftLint's length budget.
class MarkerAnchorTests: XCTestCase {

    func testMakeMarkerParsesIconAnchor() {
        let coordinate = ["lat": 1.0, "lng": 2.0] as JSObject
        let anchored = Map.makeMarker(from: [
            "coordinate": coordinate,
            "iconAnchor": ["x": 0.5, "y": 0.5] as JSObject
        ])
        XCTAssertEqual(anchored?.iconAnchor, CGPoint(x: 0.5, y: 0.5))
        // Omitted stays nil, so centerOffset keeps the bottom-centre default.
        XCTAssertNil(Map.makeMarker(from: ["coordinate": coordinate])?.iconAnchor)
        // A malformed anchor is ignored rather than half-applied.
        XCTAssertNil(Map.makeMarker(from: ["coordinate": coordinate, "iconAnchor": ["x": 0.5] as JSObject])?.iconAnchor)
    }

    func testCenterOffsetHonoursAnchor() {
        let size = CGSize(width: 40, height: 60)
        let marker = AppleMapMarker()

        // Default (nil) anchors the bottom-centre — the classic teardrop tip.
        XCTAssertEqual(marker.centerOffset(for: size), CGPoint(x: 0, y: -30))

        marker.iconAnchor = CGPoint(x: 0.5, y: 0.5) // centred, as a dot wants
        XCTAssertEqual(marker.centerOffset(for: size), .zero)

        marker.iconAnchor = CGPoint(x: 0, y: 0) // top-left corner on the coordinate
        XCTAssertEqual(marker.centerOffset(for: size), CGPoint(x: 20, y: 30))
    }

    func testApplyIconUpdatesReportsAndResets() {
        let marker = AppleMapMarker()
        marker.iconAnchor = CGPoint(x: 0.5, y: 0.5)

        // A present iconAnchor of null resets to the bottom-centre default.
        XCTAssertTrue(marker.applyIconUpdates(from: ["iconAnchor": NSNull()] as JSObject))
        XCTAssertNil(marker.iconAnchor)

        // No icon fields present → nothing changed, so no re-render is requested.
        XCTAssertFalse(marker.applyIconUpdates(from: ["title": "unrelated"] as JSObject))
    }

    func testApplyIconUpdatesUrlAndSize() {
        let marker = AppleMapMarker()

        // A url change is applied and reported (so the caller re-renders).
        XCTAssertTrue(marker.applyIconUpdates(from: ["iconUrl": "pin.png"] as JSObject))
        XCTAssertEqual(marker.iconUrl, "pin.png")

        // A present iconUrl of null clears it (and still reports a change).
        XCTAssertTrue(marker.applyIconUpdates(from: ["iconUrl": NSNull()] as JSObject))
        XCTAssertNil(marker.iconUrl)

        // A size change is applied and reported.
        XCTAssertTrue(marker.applyIconUpdates(from: ["iconSize": ["width": 30.0, "height": 40.0] as JSObject]))
        XCTAssertEqual(marker.iconSize, CGSize(width: 30, height: 40))
    }

    func testParseSizeValidAndMalformed() {
        XCTAssertEqual(
            AppleMapMarker.parseSize(["width": 12.0, "height": 24.0] as JSObject),
            CGSize(width: 12, height: 24)
        )
        // Missing a dimension, wrong type, or absent → nil (never half-applied).
        XCTAssertNil(AppleMapMarker.parseSize(["width": 12.0] as JSObject))
        XCTAssertNil(AppleMapMarker.parseSize(nil))
    }
}
