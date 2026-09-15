import XCTest

final class HIDReportTests: XCTestCase {
    func testMouseWireFormatIncludesBothScrollAxes() {
        let report = MouseReport(buttons: [.left, .right], dX: -127, dY: 127, wheel: -1, pan: 2)
        XCTAssertEqual(Array(report.data), [3, 129, 127, 255, 2])
        XCTAssertEqual(Array(MouseReport(pan: -2).data), [0, 0, 0, 0, 254])
    }

    func testBootMouseFormatExcludesBothScrollAxes() {
        let report = MouseReport(buttons: [.left, .right], dX: -127, dY: 127, wheel: -1, pan: 2)
        XCTAssertEqual(Array(report.bootData), [3, 129, 127])
        XCTAssertEqual(Array(MouseReport.zero.bootData), [0, 0, 0])
    }

    func testReleaseReportsClearEveryField() {
        XCTAssertEqual(Array(KeyboardReport.zero.data), Array(repeating: 0, count: 8))
        XCTAssertEqual(Array(MouseReport.zero.data), Array(repeating: 0, count: 5))
    }
}
