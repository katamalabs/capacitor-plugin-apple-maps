import XCTest
import MapKit
@testable import CapacitorAppleMapsPlugin

/// The pure bounds math in Geometry.swift: framing rects for fitBounds /
/// setCameraBoundary and the visible-bounds corners, including boxes that cross
/// the antimeridian.
final class GeometryTests: XCTestCase {

    // MARK: - fitBounds framing rect

    func testBoundingMapRectContainsBothCorners() {
        let southWest = CLLocationCoordinate2D(latitude: 41.0, longitude: -73.0)
        let northEast = CLLocationCoordinate2D(latitude: 43.0, longitude: -69.0)
        let rect = boundingMapRect(southwest: southWest, northeast: northEast)
        XCTAssertTrue(rect.contains(MKMapPoint(southWest)))
        XCTAssertTrue(rect.contains(MKMapPoint(northEast)))
        XCTAssertGreaterThan(rect.size.width, 0)
        XCTAssertGreaterThan(rect.size.height, 0)
    }

    /// Latitude order doesn't matter (latitude grows north but MKMapPoint.y grows
    /// south): swapping only the latitudes yields the same rect.
    func testBoundingMapRectIgnoresLatitudeOrder() {
        let rect = boundingMapRect(
            southwest: CLLocationCoordinate2D(latitude: 41.0, longitude: -73.0),
            northeast: CLLocationCoordinate2D(latitude: 43.0, longitude: -69.0)
        )
        let swapped = boundingMapRect(
            southwest: CLLocationCoordinate2D(latitude: 43.0, longitude: -73.0),
            northeast: CLLocationCoordinate2D(latitude: 41.0, longitude: -69.0)
        )
        XCTAssertEqual(rect.origin.x, swapped.origin.x, accuracy: 1e-6)
        XCTAssertEqual(rect.origin.y, swapped.origin.y, accuracy: 1e-6)
        XCTAssertEqual(rect.size.width, swapped.size.width, accuracy: 1e-6)
        XCTAssertEqual(rect.size.height, swapped.size.height, accuracy: 1e-6)
    }

    /// West of east (178 to -179) is a 3-degree box across the antimeridian, not a
    /// 357-degree one spanning the rest of the world.
    func testBoundingMapRectCrossesAntimeridian() {
        let southWest = CLLocationCoordinate2D(latitude: -18.0, longitude: 178.0)
        let northEast = CLLocationCoordinate2D(latitude: -16.0, longitude: -179.0)
        let rect = boundingMapRect(southwest: southWest, northeast: northEast)

        let degreeWidth = MKMapSize.world.width / 360
        XCTAssertEqual(rect.size.width, 3 * degreeWidth, accuracy: 1)
        XCTAssertEqual(rect.origin.x, MKMapPoint(southWest).x, accuracy: 1e-6)
        XCTAssertTrue(rect.spans180thMeridian)
    }

    // MARK: - Region corners (visible bounds math)

    func testRegionCorners() {
        let center = CLLocationCoordinate2D(latitude: 42.0, longitude: -71.0)
        let span = MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 4.0)
        let corners = regionCorners(center: center, span: span)

        XCTAssertEqual(corners.southwest.latitude, 41.0, accuracy: 1e-9)
        XCTAssertEqual(corners.southwest.longitude, -73.0, accuracy: 1e-9)
        XCTAssertEqual(corners.northeast.latitude, 43.0, accuracy: 1e-9)
        XCTAssertEqual(corners.northeast.longitude, -69.0, accuracy: 1e-9)
    }

    func testRegionCornersAcrossAntimeridianStayInRange() {
        let center = CLLocationCoordinate2D(latitude: -17.0, longitude: 179.0)
        let corners = regionCorners(center: center, span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 4.0))

        XCTAssertEqual(corners.southwest.longitude, 177.0, accuracy: 1e-9)
        XCTAssertEqual(corners.northeast.longitude, -179.0, accuracy: 1e-9)
    }

    func testRegionCornersForWholeWorldDoNotCollapse() {
        let center = CLLocationCoordinate2D(latitude: 0, longitude: 10)
        let corners = regionCorners(center: center, span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 360))

        XCTAssertEqual(corners.southwest.longitude, -180)
        XCTAssertEqual(corners.northeast.longitude, 180)
    }
}
