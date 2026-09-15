import Foundation

/// Preserve key/button/consumer transitions under Bluetooth backpressure. Only
/// adjacent pure-motion snapshots retain the previous latest-motion behavior.
struct HIDNotificationQueue<Target: Equatable> {
    struct Entry {
        let data: Data
        let target: Target
        let coalesceMotion: Bool
    }

    private var entries: [Entry] = []
    private var head = 0

    var first: Entry? {
        head < entries.count ? entries[head] : nil
    }

    mutating func append(_ data: Data, target: Target, coalesceMotion: Bool = false) {
        let entry = Entry(data: data, target: target, coalesceMotion: coalesceMotion)
        if head < entries.count, coalesceMotion, entries.last?.coalesceMotion == true, entries.last?.target == target {
            entries[entries.count - 1] = entry
        } else {
            entries.append(entry)
        }
    }

    mutating func removeFirst() {
        guard head < entries.count else { return }
        head += 1
        if head == entries.count {
            removeAll()
        } else if head >= 64, head >= entries.count / 2 {
            entries.removeFirst(head)
            head = 0
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        head = 0
    }
}
