import Foundation

enum PlaybackTime {
    private static let ticksPerSecond: Double = 10_000_000

    static func normalizedPosition(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite && seconds > 0 ? seconds : 0
    }

    static func ticks(from seconds: TimeInterval) -> Int64 {
        let normalized = normalizedPosition(seconds)
        guard normalized > 0 else { return 0 }
        let maximumSeconds = Double(Int64.max) / ticksPerSecond
        return Int64((min(normalized, maximumSeconds) * ticksPerSecond).rounded(.down))
    }
}
