/// A stopped worker must finish before another tap can own its callbacks/ports.
struct TapRunState {
    private var generation = 0
    private var worker: Int?
    var isRunning: Bool {
        worker == generation
    }

    mutating func begin() -> Int? {
        guard worker == nil else { return nil }
        generation += 1
        worker = generation
        return generation
    }

    mutating func stop() {
        generation += 1
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }

    mutating func finish(_ token: Int) {
        if worker == token { worker = nil }
    }
}
