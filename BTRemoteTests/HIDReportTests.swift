import XCTest

final class HIDReportTests: XCTestCase {
    func testExistingMouseWireFormat() {
        let report = MouseReport(buttons: [.left, .right], dX: -127, dY: 127, wheel: -1)
        XCTAssertEqual(Array(report.data), [3, 129, 127, 255])
        XCTAssertEqual(Array(MouseReport.zero.data), [0, 0, 0, 0])
    }

    func testReleaseReportsClearEveryField() {
        XCTAssertEqual(Array(KeyboardReport.zero.data), Array(repeating: 0, count: 8))
        XCTAssertEqual(Array(MouseReport.zero.data), Array(repeating: 0, count: 4))
    }
}
