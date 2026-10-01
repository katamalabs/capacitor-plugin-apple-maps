import XCTest
import CoreLocation
import Capacitor
@testable import CapacitorAppleMapsPlugin

/// The `requestPermissions` bookkeeping: which held calls get resolved, with what,
/// and when. Drives `resolvePendingPermissionCalls` directly with each status the
/// delegate can report, since the real system prompt can't be answered in a test.
final class PermissionsTests: XCTestCase {

    private lazy var plugin = CapacitorAppleMapsPlugin()

    /// A call that records the `location` state it resolves with (nil until then).
    private func makeCall(_ id: String, resolved: @escaping (String?) -> Void) throws -> CAPPluginCall {
        try XCTUnwrap(CAPPluginCall(
            callbackId: id, methodName: "requestPermissions", options: [:],
            success: { result, _ in resolved(result?.data?["location"] as? String) },
            error: { _ in XCTFail("\(id) rejected") }
        ))
    }

    func testPermissionStateMapping() {
        XCTAssertEqual(CapacitorAppleMapsPlugin.permissionState(for: .notDetermined), "prompt")
        XCTAssertEqual(CapacitorAppleMapsPlugin.permissionState(for: .denied), "denied")
        XCTAssertEqual(CapacitorAppleMapsPlugin.permissionState(for: .restricted), "denied")
        XCTAssertEqual(CapacitorAppleMapsPlugin.permissionState(for: .authorizedWhenInUse), "granted")
        XCTAssertEqual(CapacitorAppleMapsPlugin.permissionState(for: .authorizedAlways), "granted")
    }

    /// Core Location reports `.notDetermined` as soon as the manager exists, before
    /// the user answers; that must not resolve the call as "prompt".
    func testInitialNotDeterminedCallbackLeavesCallPending() throws {
        var state: String?
        plugin.pendingPermissionCalls = [try makeCall("a") { state = $0 }]

        plugin.resolvePendingPermissionCalls(with: .notDetermined)

        XCTAssertNil(state)
        XCTAssertEqual(plugin.pendingPermissionCalls.count, 1)
    }

    func testOverlappingRequestsAllResolveWithTheAnswer() throws {
        var first: String?
        var second: String?
        plugin.pendingPermissionCalls = [
            try makeCall("a") { first = $0 },
            try makeCall("b") { second = $0 }
        ]

        plugin.resolvePendingPermissionCalls(with: .authorizedWhenInUse)

        XCTAssertEqual(first, "granted")
        XCTAssertEqual(second, "granted")
        XCTAssertTrue(plugin.pendingPermissionCalls.isEmpty)
    }

    func testDeniedAnswerResolvesOnce() throws {
        var resolutions: [String?] = []
        plugin.pendingPermissionCalls = [try makeCall("a") { resolutions.append($0) }]

        plugin.resolvePendingPermissionCalls(with: .denied)
        plugin.resolvePendingPermissionCalls(with: .authorizedWhenInUse)   // a later change

        XCTAssertEqual(resolutions, ["denied"])
    }
}
