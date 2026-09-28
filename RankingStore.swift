import Foundation

/// Persists how often each search result has been launched, so frequently-used items
/// can rank higher over time — and lets that boost be cleared per item on request.
final class RankingStore {
    static let shared = RankingStore()

    private static let defaultsKey = "resultUsageCounts"
    private var counts: [String: Int]

    private init() {
        counts = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
    }

    func recordUse(_ key: String) {
        counts[key, default: 0] += 1
        persist()
    }

    func reset(_ key: String) {
        counts.removeValue(forKey: key)
        persist()
    }

    /// A small, capped bonus added to a result's text relevance. Large enough to let a
    /// frequently-used item climb over a similarly-relevant fresher one, small enough
    /// that it can never make an irrelevant match outrank a genuine one.
    func boostScore(for key: String?) -> Double {
        guard let key else { return 0 }
        let count = counts[key] ?? 0
        return Double(min(count, 20)) * 0.02
    }

    private func persist() {
        UserDefaults.standard.set(counts, forKey: Self.defaultsKey)
    }
}
