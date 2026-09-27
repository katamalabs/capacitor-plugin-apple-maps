import XCTest
import MapKit
import Capacitor
@testable import CapacitorAppleMapsPlugin

/// Headless `Map` bookkeeping: the marker/overlay/clustering state a live map
/// tracks, verified without rendering. `MKMapView` works fine off-screen in a unit
/// test, so these assert the data structures and flags Map maintains (not pixels).
/// Tests run on the main thread (XCTest's default), where `runOnMainSync` executes
/// inline; the few `DispatchQueue.main.async` setters are flushed explicitly.
final class MapStateTests: XCTestCase {

    /// The Map holds its delegate weakly, so the plugin must outlive it. A `lazy`
    /// stored property does that and is created fresh for each test instance.
    private lazy var plugin = CapacitorAppleMapsPlugin()

    private func makeMap(clustering: Bool = false) throws -> Map {
        let config = try AppleMapConfig(fromJSObject: [
            "center": ["lat": 42.0, "lng": -71.0] as JSObject,
            "zoom": 10.0,
            "clustering": clustering
        ])
        return Map(id: "test", config: config, delegate: plugin)
    }

    /// Let queued `DispatchQueue.main.async` work (e.g. render(), setMapType) run.
    /// Enqueued after those blocks on the serial main queue, so it drains them.
    private func flushMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    // MARK: - Markers

    func testAddAndRemoveMarkersTrackIds() throws {
        let map = try makeMap()
        let ids = map.addMarkers([
            ["coordinate": ["lat": 1.0, "lng": 2.0] as JSObject],
            ["coordinate": ["lat": 3.0, "lng": 4.0] as JSObject, "markerId": "custom"]
        ])
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(map.markers.count, 2)
        XCTAssertTrue(ids.contains("custom"))
        XCTAssertNotNil(map.markers["custom"])

        map.removeMarkers(["custom"])
        XCTAssertNil(map.markers["custom"])
        XCTAssertEqual(map.markers.count, 1)
    }

    func testMalformedMarkerIsSkipped() throws {
        let map = try makeMap()
        let ids = map.addMarkers([
            ["coordinate": ["lat": 1.0, "lng": 2.0] as JSObject],
            ["title": "no coordinate"]   // dropped: no coordinate
        ])
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(map.markers.count, 1)
    }

    func testUpdateMarkersAppliesFields() throws {
        let map = try makeMap()
        let id = try XCTUnwrap(map.addMarkers([["coordinate": ["lat": 1.0, "lng": 2.0] as JSObject]]).first)
        map.updateMarkers([[
            "markerId": id,
            "title": "Updated",
            "opacity": 0.4,
            "zIndex": 5.0
        ]])
        let marker = map.markers[id]
        XCTAssertEqual(marker?.title, "Updated")
        XCTAssertEqual(marker?.opacity, 0.4)
        XCTAssertEqual(marker?.zIndex, 5.0)
    }

    // MARK: - Overlays

    func testOverlayRegisterAndRemove() throws {
        let map = try makeMap()
        let polylineIds = map.addPolylines([[
            "path": [["lat": 0.0, "lng": 0.0] as JSObject, ["lat": 1.0, "lng": 1.0] as JSObject]
        ]])
        let circleIds = map.addCircles([[
            "center": ["lat": 0.0, "lng": 0.0] as JSObject, "radius": 100.0
        ]])
        XCTAssertEqual(polylineIds.count, 1)
        XCTAssertEqual(circleIds.count, 1)
        XCTAssertEqual(map.overlays.count, 2)
        XCTAssertEqual(map.overlayStyles.count, 2)

        map.removeOverlays(polylineIds + circleIds)
        XCTAssertTrue(map.overlays.isEmpty)
        XCTAssertTrue(map.overlayStyles.isEmpty)
    }

    func testMalformedOverlayIsSkipped() throws {
        let map = try makeMap()
        // A polyline needs at least two points; one point is dropped.
        let ids = map.addPolylines([["path": [["lat": 0.0, "lng": 0.0] as JSObject]]])
        XCTAssertTrue(ids.isEmpty)
        XCTAssertTrue(map.overlays.isEmpty)
    }

    // MARK: - Clustering

    func testClusteringToggleAndThreshold() throws {
        let map = try makeMap()
        XCTAssertFalse(map.clusteringEnabled)
        XCTAssertFalse(map.shouldCluster)

        map.enableClustering(minClusterSize: 3)
        XCTAssertTrue(map.clusteringEnabled)
        XCTAssertEqual(map.clusterMinSize, 3)
        XCTAssertFalse(map.shouldCluster)   // no markers yet

        _ = map.addMarkers([
            ["coordinate": ["lat": 1.0, "lng": 1.0] as JSObject],
            ["coordinate": ["lat": 2.0, "lng": 2.0] as JSObject]
        ])
        XCTAssertFalse(map.shouldCluster)   // 2 < 3
        _ = map.addMarkers([["coordinate": ["lat": 3.0, "lng": 3.0] as JSObject]])
        XCTAssertTrue(map.shouldCluster)    // 3 >= 3

        map.disableClustering()
        XCTAssertFalse(map.clusteringEnabled)
        XCTAssertFalse(map.shouldCluster)
    }

    func testConfigClusteringStartsEnabledWithDefaultMinSize() throws {
        let map = try makeMap(clustering: true)
        XCTAssertTrue(map.clusteringEnabled)
        XCTAssertEqual(map.clusterMinSize, 2)
    }

    func testGeodesicPolylineUsesGeodesicClass() throws {
        let map = try makeMap()
        let ids = map.addPolylines([[
            "path": [["lat": 0.0, "lng": 0.0] as JSObject, ["lat": 10.0, "lng": 80.0] as JSObject],
            "geodesic": true
        ]])
        let overlay = try XCTUnwrap(map.overlays[try XCTUnwrap(ids.first)])
        XCTAssertTrue(overlay is MKGeodesicPolyline)

        // A plain polyline is not geodesic.
        let plainId = try XCTUnwrap(map.addPolylines([[
            "path": [["lat": 0.0, "lng": 0.0] as JSObject, ["lat": 1.0, "lng": 1.0] as JSObject]
        ]]).first)
        XCTAssertFalse(try XCTUnwrap(map.overlays[plainId]) is MKGeodesicPolyline)
    }

    // MARK: - Selection

    func testSelectMarkerReportsFoundState() throws {
        let map = try makeMap()
        let id = try XCTUnwrap(map.addMarkers([["coordinate": ["lat": 1.0, "lng": 2.0] as JSObject]]).first)
        XCTAssertTrue(map.selectMarker(id))
        XCTAssertFalse(map.selectMarker("does-not-exist"))
        map.deselectMarker()   // no-op with nothing open; must not crash
    }

    // MARK: - Camera boundary

    func testCameraBoundarySetAndClear() throws {
        let map = try makeMap()
        map.setCameraBoundary(
            southwest: CLLocationCoordinate2D(latitude: 40, longitude: -75),
            northeast: CLLocationCoordinate2D(latitude: 43, longitude: -70)
        )
        XCTAssertNotNil(map.mapView.cameraBoundary)

        map.setCameraBoundary(southwest: nil, northeast: nil)
        XCTAssertNil(map.mapView.cameraBoundary)
    }

    // MARK: - Map type

    func testSetMapTypeRoundTripsThroughMap() throws {
        let map = try makeMap()
        map.setMapType("hybrid")
        flushMainQueue()
        XCTAssertEqual(map.currentMapType(), "hybrid")

        map.setMapType("satellite")
        flushMainQueue()
        XCTAssertEqual(map.currentMapType(), "satellite")
    }
}
