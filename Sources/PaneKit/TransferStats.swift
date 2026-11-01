import Foundation

/// Speed and time left for a long copy. Pure: give it the bytes done and when.
public struct TransferStats: Sendable {
    private var lastBytes: Int64 = 0
    private var lastTime: Date?
    private var smoothed: Double?

    public init() {}

    /// Bytes per second, smoothed so the number does not jump. nil until two readings are half a second apart.
    public var bytesPerSecond: Double? { smoothed }

    public mutating func add(bytes: Int64, at time: Date) {
        guard let last = lastTime else { lastBytes = bytes; lastTime = time; return }
        let seconds = time.timeIntervalSince(last)
        guard seconds >= 0.5 else { return }
        let rate = Double(max(bytes - lastBytes, 0)) / seconds
        smoothed = smoothed.map { $0 * 0.7 + rate * 0.3 } ?? rate
        lastBytes = bytes
        lastTime = time
    }

    public func secondsLeft(done: Int64, total: Int64) -> Double? {
        guard let speed = smoothed, speed > 1, total > done else { return nil }
        return Double(total - done) / speed
    }

    /// "12 MB of 40 MB · 3.2 MB/s · 9 seconds left". Parts that are not known yet are left out.
    public func describe(done: Int64, total: Int64) -> String {
        var parts: [String] = []
        let size = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        if total > 0 { parts.append("\(size(done)) of \(size(total))") }
        if let speed = smoothed, speed > 1 { parts.append("\(size(Int64(speed)))/s") }
        if let left = secondsLeft(done: done, total: total) { parts.append(Self.words(forSeconds: left)) }
        return parts.joined(separator: " · ")
    }

    static func words(forSeconds seconds: Double) -> String {
        let whole = Int(seconds.rounded(.up))
        if whole < 60 { return "\(max(whole, 1)) second\(whole == 1 ? "" : "s") left" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") left" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr left" : "\(hours) hr \(rest) min left"
    }
}
