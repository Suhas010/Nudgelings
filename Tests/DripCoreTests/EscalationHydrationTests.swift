import Foundation
import Testing
@testable import DripCore

// MARK: Nudge ladder

private func plan(_ nudges: [NudgeType], _ p: Pushiness = .gentle, minutes: Double) -> NudgePlan {
    Nudging.plan(nudges: nudges, retryMinutes: 10, pushiness: p, elapsed: minutes * 60)
}

@Test func firstAttemptShowsExactlyThePickedNudges() {
    let p = plan([.toast, .sound], minutes: 0)
    #expect(p.types == [.toast, .sound])
    #expect(p.attempt == 0)
    #expect(p.showing)
    #expect(!p.gaveUp)
}

@Test func nudgeGoesQuietAfterItsShowWindowUntilTheRetry() {
    let p = plan([.toast], minutes: 2)
    #expect(!p.showing)
    #expect(p.attempt == 0)
}

@Test func ignoredNudgeRetriesOneRungLouder() {
    let p = plan([.toast, .sound], minutes: 10)
    #expect(p.attempt == 1)
    #expect(p.showing)
    #expect(p.types == [.toast, .sound, .menuShow])   // toast is the loudest pick → next rung up
}

@Test func gentleGivesUpAfterTwoRetriesAndNeverTakesOver() {
    let second = plan([.toast], minutes: 20)
    #expect(second.attempt == 2)
    #expect(!second.types.contains(where: { $0.blocksScreen }))
    #expect(plan([.toast], minutes: 30).gaveUp)
    #expect(plan([.gag], minutes: 20).types == [.gag])   // already at gentle's ceiling
}

@Test func nagCanReachTakeoverOnlyAfterTwoIgnores() {
    #expect(!plan([.gag], .nag, minutes: 5).types.contains(.takeover))   // retry every 5 min
    #expect(!plan([.gag], .nag, minutes: 5).types.contains(where: { $0.blocksScreen }))
    #expect(plan([.gag], .nag, minutes: 10).types.contains(.takeover))
    #expect(!plan([.gag], .nag, minutes: 15).gaveUp)
    #expect(plan([.gag], .nag, minutes: 20).gaveUp)
}

@Test func maxClimbsTwoRungsPerIgnore() {
    let p = plan([.menuWiggle], .max, minutes: 3)
    #expect(p.attempt == 1)
    #expect(p.types == [.menuWiggle, .toast])
}

@Test func takeoverPicksStayTakeovers() {
    #expect(plan([.takeover], minutes: 0).types == [.takeover])
    #expect(plan([.miniGame], minutes: 10).types == [.miniGame])
}

@Test func negativeElapsedIsTreatedAsJustFired() {
    #expect(Nudging.plan(nudges: [.toast], retryMinutes: 10, pushiness: .gentle, elapsed: -30).attempt == 0)
}

// MARK: Hydration

@Test func hydrationDrainsToZeroOverTwiceTheWaterInterval() {
    let start = HydrationState(level: 1, updatedAt: at(28, 9))
    #expect(abs(start.drained(to: at(28, 9, 45), waterIntervalMinutes: 45).level - 0.5) < 0.0001)
    #expect(start.drained(to: at(28, 10, 30), waterIntervalMinutes: 45).level == 0)
    #expect(start.drained(to: at(28, 12), waterIntervalMinutes: 45).level == 0)
}

@Test func hydrationNeverDrainsBackwardsInTime() {
    let s = HydrationState(level: 0.4, updatedAt: at(28, 10))
    #expect(s.drained(to: at(28, 9), waterIntervalMinutes: 45).level == 0.4)
}

@Test func drinkingAddsThirtyFivePercentCapped() {
    #expect(abs(HydrationState(level: 0.2, updatedAt: at(28, 9)).drinking(at: at(28, 9)).level - 0.55) < 0.0001)
    #expect(HydrationState(level: 0.8, updatedAt: at(28, 9)).drinking(at: at(28, 9)).level == 1)
}

@Test func moodThresholds() {
    func mood(_ l: Double) -> Mood { HydrationState(level: l, updatedAt: at(28, 9)).mood }
    #expect(mood(1) == .hydrated)
    #expect(mood(0.66) == .hydrated)
    #expect(mood(0.65) == .thirsty)
    #expect(mood(0.33) == .thirsty)
    #expect(mood(0.32) == .parched)
}
