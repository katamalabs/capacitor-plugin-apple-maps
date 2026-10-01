import XCTest
import MapKit
import Capacitor
@testable import CapacitorAppleMapsPlugin

/// The overlay compositing `takeSnapshot` does on top of the base-map image,
/// rendered into a plain bitmap so the result can be checked pixel by pixel.
/// Coordinates are projected linearly, 1 degree = 10px, on a 100x100 canvas.
final class SnapshotDrawingTests: XCTestCase {

    private lazy var plugin = CapacitorAppleMapsPlugin()
    private let size = 100

    private func makeMap() throws -> Map {
        let config = try AppleMapConfig(fromJSObject: [
            "center": ["lat": 5.0, "lng": 5.0] as JSObject,
            "zoom": 10.0
        ])
        return Map(id: "test", config: config, delegate: plugin)
    }

    private func coord(_ lat: Double, _ lng: Double) -> JSObject {
        ["lat": lat, "lng": lng]
    }

    /// Draw the map's overlays onto a transparent RGBA canvas and return a reader
    /// for the alpha and red channels at a pixel (x right, y down).
    private func render(_ map: Map) throws -> (_ x: Int, _ y: Int) -> (alpha: UInt8, red: UInt8) {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Flip to UIKit's top-left origin, which is what the snapshot draws in.
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        map.drawOverlays(into: ctx) { CGPoint(x: $0.longitude * 10, y: $0.latitude * 10) }

        // Copy out: the context owns its buffer and frees it with the context.
        let bytes = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let pixels = Array(UnsafeBufferPointer(start: bytes, count: size * size * 4))
        let width = size
        return { x, y in
            let offset = (y * width + x) * 4
            return (alpha: pixels[offset + 3], red: pixels[offset])
        }
    }

    func testPolygonHoleIsLeftUnfilled() throws {
        let map = try makeMap()
        _ = map.addPolygons([[
            "paths": [
                [coord(1, 1), coord(1, 9), coord(9, 9), coord(9, 1)],   // exterior: 10..90px
                [coord(4, 4), coord(4, 6), coord(6, 6), coord(6, 4)]    // hole: 40..60px
            ],
            "fillColor": "#FF0000",
            "fillOpacity": 1.0,
            "strokeColor": "#0000FF",
            "strokeWeight": 1.0
        ]])

        let pixel = try render(map)
        XCTAssertEqual(pixel(25, 25).alpha, 255, "inside the polygon, outside the hole: filled")
        XCTAssertEqual(pixel(25, 25).red, 255)
        XCTAssertEqual(pixel(50, 50).alpha, 0, "centre of the hole: nothing drawn")
        XCTAssertEqual(pixel(5, 5).alpha, 0, "outside the polygon: nothing drawn")
    }

    func testDashedPolylineHasGapsAndSolidOneDoesNot() throws {
        // Count transparent pixels along the line's centre row (y = 50px).
        func gaps(dashPattern: [Double]?) throws -> Int {
            let map = try makeMap()
            var line: JSObject = ["path": [coord(5, 0), coord(5, 10)], "strokeWeight": 4.0]
            if let dashPattern = dashPattern { line["lineDashPattern"] = dashPattern }
            _ = map.addPolylines([line])
            let pixel = try render(map)
            return (5..<95).filter { pixel($0, 50).alpha == 0 }.count
        }

        XCTAssertEqual(try gaps(dashPattern: nil), 0)
        // [10, 10] over 90px: roughly half the row is gap.
        let dashed = try gaps(dashPattern: [10, 10])
        XCTAssertGreaterThan(dashed, 30)
        XCTAssertLessThan(dashed, 60)
    }
}
