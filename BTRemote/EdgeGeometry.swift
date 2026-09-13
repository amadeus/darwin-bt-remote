import CoreGraphics
import Foundation

enum DisplayEdge: String, CaseIterable, Identifiable, Sendable {
    case left, right, top, bottom

    var id: String {
        rawValue
    }
}

struct EdgeGeometry: Equatable, Sendable {
    let bounds: CGRect
    let edge: DisplayEdge
    let otherDisplays: [CGRect]
    var cornerSize: Double = 0

    var parkingPoint: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func isAtEdge(_ point: CGPoint) -> Bool {
        guard !bounds.isEmpty else { return false }
        let along: Double
        let length: Double
        let outside: CGPoint
        switch edge {
        case .left:
            guard abs(point.x - bounds.minX) <= 1 else { return false }
            along = point.y - bounds.minY
            length = bounds.height
            outside = CGPoint(x: bounds.minX - 1, y: point.y)
        case .right:
            guard abs(point.x - (bounds.maxX - 1)) <= 1 else { return false }
            along = point.y - bounds.minY
            length = bounds.height
            outside = CGPoint(x: bounds.maxX, y: point.y)
        case .top:
            guard abs(point.y - bounds.minY) <= 1 else { return false }
            along = point.x - bounds.minX
            length = bounds.width
            outside = CGPoint(x: point.x, y: bounds.minY - 1)
        case .bottom:
            guard abs(point.y - (bounds.maxY - 1)) <= 1 else { return false }
            along = point.x - bounds.minX
            length = bounds.width
            outside = CGPoint(x: point.x, y: bounds.maxY)
        }
        return along >= cornerSize && along < length - cornerSize && !otherDisplays.contains { $0.contains(outside) }
    }

    func isOutward(dx: Int64, dy: Int64) -> Bool {
        switch edge {
        case .left: dx < 0
        case .right: dx > 0
        case .top: dy < 0
        case .bottom: dy > 0
        }
    }

    func inset(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX + 2), bounds.maxX - 3),
            y: min(max(point.y, bounds.minY + 2), bounds.maxY - 3)
        )
    }
}
