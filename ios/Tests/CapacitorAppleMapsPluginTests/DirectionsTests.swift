import XCTest
import MapKit
@testable import CapacitorAppleMapsPlugin

// MARK: - Directions helpers
final class DirectionsTests: XCTestCase {

    // MARK: Transport type mapping

    func testTransportTypeDefaultsToDriving() {
        XCTAssertEqual(parseTransportType(nil), .automobile)
        XCTAssertEqual(parseTransportType("automobile"), .automobile)
        XCTAssertEqual(parseTransportType("driving"), .automobile)
    }

    func testTransportTypeWalkingAndTransit() {
        XCTAssertEqual(parseTransportType("walking"), .walking)
        XCTAssertEqual(parseTransportType("transit"), .transit)
    }

    /// An unrecognised mode must still route, falling back to driving.
    func testTransportTypeUnknownFallsBackToDriving() {
        XCTAssertEqual(parseTransportType("teleport"), .automobile)
    }

    // MARK: Departure/arrival date parsing

    func testEpochDateAbsentWhenNilOrNonPositive() {
        XCTAssertNil(parseEpochDate(nil))
        XCTAssertNil(parseEpochDate(0))
        XCTAssertNil(parseEpochDate(-1))
    }

    /// JS passes `Date.getTime()` in milliseconds; MapKit wants seconds.
    func testEpochDateConvertsMillisToSeconds() throws {
        let date = try XCTUnwrap(parseEpochDate(1_700_000_000_000))
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    // MARK: Failure classification

    /// No error, and "no route exists", are answers (an empty list), not failures.
    func testDirectionsFailureTreatsNotFoundAsEmpty() {
        XCTAssertNil(directionsFailure(nil))
        XCTAssertNil(directionsFailure(MKError(.directionsNotFound)))
    }

    /// Throttling, server errors and offline must surface as failures so an empty
    /// result is never mistaken for "Apple could not answer".
    func testDirectionsFailureSurfacesRealFailures() {
        XCTAssertNotNil(directionsFailure(MKError(.loadingThrottled)))
        XCTAssertNotNil(directionsFailure(MKError(.serverFailure)))
        XCTAssertNotNil(directionsFailure(URLError(.notConnectedToInternet)))
    }

    // MARK: Polyline decoding

    func testPolylineCoordinatesRoundTrip() throws {
        let input = [
            CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        ]
        let path = polylineCoordinates(MKPolyline(coordinates: input, count: input.count))
        XCTAssertEqual(path.count, 2)
        XCTAssertEqual(try XCTUnwrap(path[0]["lat"]), 42.3601, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(path[0]["lng"]), -71.0589, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(path[1]["lat"]), 40.7128, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(path[1]["lng"]), -74.0060, accuracy: 0.0001)
    }

    func testPolylineCoordinatesEmpty() {
        XCTAssertTrue(polylineCoordinates(MKPolyline(coordinates: [], count: 0)).isEmpty)
    }
}
