import CoreGraphics
import XCTest

final class ReturnMotionProbeTests: XCTestCase {
    func testDetectsRawMovementWhileCursorRemainsFixed() {
        var probe = ReturnMotionProbe(startedAt: 0, origin: CGPoint(x: 100, y: 200))
        XCTAssertNil(probe.observe(now: 0.01, position: probe.origin, hasDelta: true))
        XCTAssertNil(probe.observe(now: 0.1, position: probe.origin, hasDelta: true))
        XCTAssertNil(probe.observe(now: 0.2, position: probe.origin, hasDelta: false))
        XCTAssertEqual(
            probe.observe(now: 0.25, position: CGPoint(x: 101, y: 200), hasDelta: true),
            "return motion: firstRawMs=10 firstMoveMs=250 fixedPositionEvents=2"
        )
    }

    func testIdleUserIsNotReportedAsSuppressedMotion() {
        var probe = ReturnMotionProbe(startedAt: 0, origin: .zero)
        XCTAssertNil(probe.observe(now: 0.5, position: .zero, hasDelta: false))
        XCTAssertNil(probe.expired(now: 0.9))
        XCTAssertEqual(
            probe.expired(now: 1),
            "return motion: firstRawMs=-1 firstMoveMs=unobserved fixedPositionEvents=0"
        )
    }
}
