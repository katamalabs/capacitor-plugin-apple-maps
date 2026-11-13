import XCTest
import MapKit
@testable import CapacitorAppleMapsPlugin

// MARK: - Open in Maps helpers
final class OpenInMapsTests: XCTestCase {

    // MARK: Directions-mode mapping

    /// An omitted or unrecognised mode must still launch, defaulting to driving.
    func testDirectionsModeDefaultsToDriving() {
        XCTAssertEqual(launchDirectionsMode(nil), MKLaunchOptionsDirectionsModeDriving)
        XCTAssertEqual(launchDirectionsMode("automobile"), MKLaunchOptionsDirectionsModeDriving)
        XCTAssertEqual(launchDirectionsMode("teleport"), MKLaunchOptionsDirectionsModeDriving)
    }

    func testDirectionsModeWalkingAndTransit() {
        XCTAssertEqual(launchDirectionsMode("walking"), MKLaunchOptionsDirectionsModeWalking)
        XCTAssertEqual(launchDirectionsMode("transit"), MKLaunchOptionsDirectionsModeTransit)
    }
}
