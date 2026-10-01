import XCTest
import MapKit
import Capacitor
@testable import CapacitorAppleMapsPlugin

/// Mount reporting. A unit test has no bridge and so no WKWebView, which makes
/// it the "container never turns up" case: the mount must give up after its
/// retries and say so, instead of reporting a blank map as ready.
final class MountTests: XCTestCase {

    private lazy var plugin = CapacitorAppleMapsPlugin()

    /// Every retry, plus slack.
    private let mountTimeout = Double(Map.mountAttempts) * Map.mountRetryInterval + 2

    private func makeConfig() throws -> AppleMapConfig {
        try AppleMapConfig(fromJSObject: [
            "center": ["lat": 42.0, "lng": -71.0] as JSObject,
            "zoom": 10.0,
            "width": 100.0,
            "height": 100.0
        ])
    }

    func testMountFailsWhenNoContainerAppears() throws {
        let done = expectation(description: "mount finished")
        var outcomes: [MountOutcome] = []
        let map = Map(id: "m", config: try makeConfig(), delegate: plugin) { outcome in
            outcomes.append(outcome)
            done.fulfill()
        }
        wait(for: [done], timeout: mountTimeout)

        XCTAssertEqual(outcomes.count, 1)
        guard case .containerNotFound = outcomes.first else {
            return XCTFail("expected containerNotFound, got \(String(describing: outcomes.first))")
        }
        XCTAssertNil(map.mapView.superview)
    }

    func testDestroyBeforeMountReportsDestroyedOnce() throws {
        let done = expectation(description: "mount finished")
        var outcomes: [MountOutcome] = []
        let map = Map(id: "m", config: try makeConfig(), delegate: plugin) { outcome in
            outcomes.append(outcome)
            done.fulfill()
        }
        map.destroy()
        wait(for: [done], timeout: mountTimeout)

        // Let any retry still queued run; it must not report a second time.
        let drained = expectation(description: "retries drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + Map.mountRetryInterval * 3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        XCTAssertEqual(outcomes.count, 1)
        guard case .destroyed = outcomes.first else {
            return XCTFail("expected destroyed, got \(String(describing: outcomes.first))")
        }
    }

    func testCreateRejectsAndForgetsMapThatCannotMount() throws {
        let rejected = expectation(description: "create rejected")
        var code: String?
        let options = JSTypes.coerceDictionaryToJSObject([
            "id": "m",
            "config": ["center": ["lat": 42.0, "lng": -71.0], "zoom": 10.0, "width": 100.0, "height": 100.0]
        ]) ?? [:]
        let call = try XCTUnwrap(CAPPluginCall(
            callbackId: "c", methodName: "create", options: options,
            success: { _, _ in XCTFail("create should not resolve without a container") },
            error: { error in
                code = error?.code
                rejected.fulfill()
            }
        ))

        plugin.create(call)
        XCTAssertNotNil(plugin.maps["m"], "map is registered while it mounts")
        wait(for: [rejected], timeout: mountTimeout)

        XCTAssertEqual(code, PluginError.mountFailed)
        XCTAssertNil(plugin.maps["m"])
    }
}
