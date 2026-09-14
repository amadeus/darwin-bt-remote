import Foundation

struct ClipboardRevision {
    private(set) var observed: Int?
    private(set) var local = 0
    mutating func capture(_ value: Int) {
        observed = value; local = value
    }

    mutating func imported(_ value: Int) {
        observed = value
    }

    func canApply(expectedLocal: Int, current: Int) -> Bool {
        local == expectedLocal && observed == current
    }
}
