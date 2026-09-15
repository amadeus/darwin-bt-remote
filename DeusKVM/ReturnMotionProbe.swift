import CoreGraphics
import Foundation

/// Reports timing and counts; never logs input contents or pointer coordinates.
struct ReturnMotionProbe {
    let startedAt: TimeInterval
    let origin: CGPoint
    private(set) var firstRawMs: Int?
    private(set) var fixedPositionEvents = 0

    mutating func observe(now: TimeInterval, position: CGPoint, hasDelta: Bool) -> String? {
        guard hasDelta else { return nil }
        let elapsed = Int((now - startedAt) * 1000)
        if firstRawMs == nil { firstRawMs = elapsed }
        if abs(position.x - origin.x) >= 1 || abs(position.y - origin.y) >= 1 {
            return "return motion: firstRawMs=\(firstRawMs ?? -1) firstMoveMs=\(elapsed) fixedPositionEvents=\(fixedPositionEvents)"
        }
        fixedPositionEvents += 1
        return nil
    }

    func expired(now: TimeInterval) -> String? {
        guard now - startedAt >= 1 else { return nil }
        return "return motion: firstRawMs=\(firstRawMs ?? -1) firstMoveMs=unobserved fixedPositionEvents=\(fixedPositionEvents)"
    }
}
