import Foundation

enum ScanPhase: Equatable, Sendable {
    case idle
    /// Reading items one by one; `done` of `total` is real progress.
    case scanning(done: Int, total: Int)
    /// Every item has been read; results are being compared and measured. Not finished yet.
    case analyzing
    case finished
    case failed(String)

    /// True for both scanning and analyzing: the work isn't finished until `.finished`.
    var isScanning: Bool {
        switch self {
        case .scanning, .analyzing: true
        default: false
        }
    }

    var isAnalyzing: Bool { self == .analyzing }

    var fraction: Double? {
        guard case let .scanning(done, total) = self, total > 0 else { return nil }
        return min(Double(done) / Double(total), 1)
    }

    var failureMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    var counts: (done: Int, total: Int)? {
        if case let .scanning(done, total) = self { return (done, total) }
        return nil
    }
}
