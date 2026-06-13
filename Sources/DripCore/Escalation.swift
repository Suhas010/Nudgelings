import Foundation

/// What an active reminder should be doing right now.
public struct NudgePlan: Equatable, Sendable {
    /// Nudge types to present in this attempt (the picks, plus one louder rung once ignored).
    public var types: [NudgeType]
    /// 0 = first try; each ignore adds one.
    public var attempt: Int
    /// Inside this attempt's show window. Between retries only the menu-bar character hops.
    public var showing: Bool
    /// Ignored past the last retry: the character lets it go.
    public var gaveUp: Bool
}

/// The ignore ladder.
///
///   attempt 0 ──(retry)──▶ attempt 1 ──(retry)──▶ … ──▶ gave up
///   picks        picks + one louder rung          (gentle: 2 retries, nag: 3, max: 4)
///   each attempt shows for `showSeconds`, then goes quiet until the next retry
public enum Nudging {
    public static let showSeconds: TimeInterval = 90

    public static func retrySeconds(retryMinutes: Int, pushiness: Pushiness) -> TimeInterval {
        max(60, Double(retryMinutes) * 60 * pushiness.retryFactor)
    }

    public static func plan(nudges: [NudgeType], retryMinutes: Int, pushiness: Pushiness,
                            elapsed: TimeInterval) -> NudgePlan {
        let retry = retrySeconds(retryMinutes: retryMinutes, pushiness: pushiness)
        let e = max(0, elapsed)
        let attempt = Int(e / retry)
        guard attempt <= pushiness.maxRetries else {
            return NudgePlan(types: [], attempt: attempt, showing: false, gaveUp: true)
        }
        var types = nudges.isEmpty ? [NudgeType.menuWiggle] : nudges
        if attempt > 0 {
            let loudest = types.map(\.rung).max() ?? 0
            let ceiling = attempt >= pushiness.ignoresBeforeTakeover ? pushiness.ceiling.rung
                                                                     : min(pushiness.ceiling.rung, NudgeType.gag.rung)
            let target = min(loudest + attempt * pushiness.rungsPerRetry, ceiling)
            if target > loudest { types.append(NudgeType.allCases[target]) }
        }
        let showing = e - Double(attempt) * retry < showSeconds
        return NudgePlan(types: types, attempt: attempt, showing: showing, gaveUp: false)
    }
}
