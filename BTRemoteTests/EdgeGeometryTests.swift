import CoreGraphics
import XCTest

final class EdgeGeometryTests: XCTestCase {
    func testSharedEdgeOnlyArmsOnExposedSegment() {
        let geometry = EdgeGeometry(
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), edge: .right,
            otherDisplays: [CGRect(x: 1920, y: 0, width: 1920, height: 600)]
        )
        XCTAssertFalse(geometry.isAtEdge(CGPoint(x: 1919, y: 300)))
        XCTAssertTrue(geometry.isAtEdge(CGPoint(x: 1919, y: 800)))
        XCTAssertFalse(geometry.isAtEdge(CGPoint(x: 1000, y: 800)))
        XCTAssertTrue(geometry.isOutward(dx: 1, dy: 0))
        XCTAssertFalse(geometry.isOutward(dx: -1, dy: 0))
    }

    func testNegativeDisplayCoordinatesAndCorners() {
        let geometry = EdgeGeometry(
            bounds: CGRect(x: -1920, y: -1080, width: 1920, height: 1080), edge: .left,
            otherDisplays: [], cornerSize: 20
        )
        XCTAssertTrue(geometry.isAtEdge(CGPoint(x: -1920, y: -500)))
        XCTAssertFalse(geometry.isAtEdge(CGPoint(x: -1920, y: -1070)))
        XCTAssertEqual(geometry.inset(CGPoint(x: -1920, y: -500)), CGPoint(x: -1918, y: -500))
    }
}
