import XCTest

final class HIDNotificationQueueTests: XCTestCase {
    func testMovementCannotOverwriteControlAltDeleteOrItsRelease() {
        var queue = HIDNotificationQueue<Int>()
        let down = KeyboardReport(modifiers: [.leftCtrl, .leftAlt], keys: [.deleteForward]).data
        queue.append(down, target: 2)
        queue.append(Data([1]), target: 1, coalesceMotion: true)
        queue.append(Data([2]), target: 1, coalesceMotion: true)
        queue.append(KeyboardReport.zero.data, target: 2)
        XCTAssertEqual(queue.first?.data, down)
        queue.removeFirst()
        XCTAssertEqual(queue.first?.data, Data([2]))
        queue.removeFirst()
        XCTAssertEqual(queue.first?.data, KeyboardReport.zero.data)
        queue.removeFirst()
        XCTAssertNil(queue.first)
    }

    func testCapsLockAndConsumerPulsesArePreservedInOrder() {
        var queue = HIDNotificationQueue<Int>()
        let packets: [(Int, Data)] = [
            (2, KeyboardReport(keys: [.capsLock]).data), (2, KeyboardReport.zero.data),
            (6, ConsumerReport(key: .volumeUp).data), (6, ConsumerReport.zero.data)
        ]
        for (target, data) in packets {
            queue.append(data, target: target)
        }
        for (target, data) in packets {
            XCTAssertEqual(queue.first?.target, target)
            XCTAssertEqual(queue.first?.data, data)
            queue.removeFirst()
        }
        XCTAssertNil(queue.first)
    }

    func testCompactionAndTargetResetCannotReplayOldInput() {
        var queue = HIDNotificationQueue<Int>()
        for n in 0 ..< 200 {
            queue.append(Data([UInt8(n)]), target: 2)
        }
        for n in 0 ..< 150 {
            XCTAssertEqual(queue.first?.data, Data([UInt8(n)]))
            queue.removeFirst()
        }
        queue.removeAll()
        queue.append(Data([255]), target: 6)
        XCTAssertEqual(queue.first?.data, Data([255]))
        queue.removeFirst()
        XCTAssertNil(queue.first)
    }
}
