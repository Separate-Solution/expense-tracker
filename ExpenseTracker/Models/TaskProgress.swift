import Foundation

/// How far along a long data task is, for the overlay to draw.
struct TaskProgress: Equatable {
    /// What the task is, e.g. "Importing transactions".
    var label: String
    /// 0...1. Clamped on the way in so a miscounted total can't overfill the ring.
    var fraction: Double

    init(label: String, fraction: Double = 0) {
        self.label = label
        self.fraction = min(1, max(0, fraction))
    }

    /// The whole-number percentage shown in the middle of the ring.
    var percent: Int { Int((fraction * 100).rounded()) }

    /// Moves the bar, keeping the same label.
    /// - Parameter fraction: The new position, 0...1.
    mutating func advance(to fraction: Double) {
        self.fraction = min(1, max(0, fraction))
    }
}

/// Reports how far through a run of items something is, without flooding the
/// UI: an import of ten thousand rows should redraw about a hundred times, not
/// ten thousand.
struct ProgressTicker {
    private let total: Int
    private let stride: Int
    private let report: (Double) -> Void

    /// - Parameters:
    ///   - total: How many items the task will process; zero is tolerated.
    ///   - steps: Roughly how many updates to emit across the whole run.
    ///   - report: Called with the fraction done, 0...1.
    init(total: Int, steps: Int = 100, report: @escaping (Double) -> Void) {
        self.total = total
        self.stride = Swift.max(1, total / Swift.max(1, steps))
        self.report = report
    }

    /// Reports progress after `completed` items, on the stride or at the end.
    /// - Parameter completed: How many items are done.
    /// - Returns: True when an update was emitted, so the caller knows a yield
    ///   is worth doing.
    @discardableResult
    func tick(completed: Int) -> Bool {
        guard total > 0 else { return false }
        guard completed % stride == 0 || completed == total else { return false }
        report(Double(completed) / Double(total))
        return true
    }
}
