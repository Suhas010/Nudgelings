import Foundation
import Testing
@testable import DripCore

private func settings(_ enabled: HabitKind...) -> Settings {
    var s = Settings.initial
    for k in enabled { s.habits[k]!.enabled = true }
    return s
}

private func engine(_ enabled: HabitKind..., now: Date = at(28, 9)) -> ReminderEngine {
    var s = Settings.initial
    for k in enabled { s.habits[k]!.enabled = true }
    return ReminderEngine(settings: s, state: nil, now: now, calendar: cal)
}

@Test func enabledHabitFiresWhenDue() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 44), hushed: false)
    #expect(e.state.active == nil)
    e.tick(now: at(28, 9, 45), hushed: false)
    #expect(e.state.active?.kind == .water)
    #expect(e.plan(now: at(28, 9, 45))?.types == [.toast, .sound])
}

@Test func disabledHabitsNeverFire() {
    var e = engine()
    e.tick(now: at(28, 17), hushed: false)
    #expect(e.state.active == nil)
}

@Test func completingWaterRecordsDrinkAndReschedules() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    let before = e.state.hydration.level
    e.complete(now: at(28, 9, 46))
    #expect(e.state.active == nil)
    #expect(e.state.lastDone[.water] == at(28, 9, 46))
    #expect(e.state.nextDue[.water] == at(28, 10, 31))
    #expect(e.state.stats.done[.water] == 1)
    #expect(e.state.hydration.level > before)
}

@Test func onlyOneActiveReminderOthersQueueInHabitOrder() {
    var s = settings(.water, .eyes)
    s.habits[.water]!.schedule = .every(minutes: 20, anchor: .lastDone)
    var e = ReminderEngine(settings: s, state: nil, now: at(28, 9), calendar: cal)
    e.tick(now: at(28, 9, 20), hushed: false)
    #expect(e.state.active?.kind == .water)
    #expect(e.state.queued == [.eyes])
    e.complete(now: at(28, 9, 21))
    e.tick(now: at(28, 9, 21, 1), hushed: false)
    #expect(e.state.active?.kind == .eyes)
    #expect(e.state.queued.isEmpty)
}

@Test func dueHabitIsNotQueuedTwice() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: true)
    e.tick(now: at(28, 9, 46), hushed: true)
    #expect(e.state.queued == [.water])
}

@Test func hushQueuesThenFiresTwoMinutesAfterHushEnds() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: true)
    #expect(e.state.active == nil)
    #expect(e.state.queued == [.water])
    e.tick(now: at(28, 10, 0), hushed: false)          // hush ended
    e.tick(now: at(28, 10, 1), hushed: false)
    #expect(e.state.active == nil)
    e.tick(now: at(28, 10, 2, 1), hushed: false)
    #expect(e.state.active?.kind == .water)
    #expect(e.state.active?.firedAt == at(28, 10, 2, 1))
}

@Test func activeReminderIsPausedByHushAndRestartsGently() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    e.tick(now: at(28, 9, 50), hushed: true)
    #expect(e.state.active == nil)
    #expect(e.state.queued == [.water])
    e.tick(now: at(28, 10, 30), hushed: false)
    e.tick(now: at(28, 10, 33), hushed: false)
    #expect(e.plan(now: at(28, 10, 33))?.attempt == 0)
    #expect(e.plan(now: at(28, 10, 33))?.showing == true)
}

@Test func snoozeRefiresFiveMinutesLater() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    e.snooze(now: at(28, 9, 46))
    #expect(e.state.active == nil)
    #expect(e.state.stats.snoozes == 1)
    e.tick(now: at(28, 9, 50), hushed: false)
    #expect(e.state.active == nil)
    e.tick(now: at(28, 9, 51), hushed: false)
    #expect(e.state.active?.kind == .water)
}

@Test func skipCountsAndReschedulesWithoutCredit() {
    var e = engine(.eyes)
    e.tick(now: at(28, 9, 20), hushed: false)
    e.skip(now: at(28, 9, 21))
    #expect(e.state.active == nil)
    #expect(e.state.stats.skipped[.eyes] == 1)
    #expect(e.state.stats.done[.eyes] == nil)
    #expect(e.state.nextDue[.eyes] == at(28, 9, 41))
}

@Test func planFollowsTheIgnoreLadderForActiveReminder() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    #expect(e.plan(now: at(28, 9, 45))?.attempt == 0)
    #expect(e.plan(now: at(28, 9, 55))?.attempt == 1)
}

@Test func ignoredToTheEndTheCharacterGivesUpAndReschedules() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    e.tick(now: at(28, 10, 15), hushed: false)        // 3 attempts (0, 10, 20 min) have passed
    #expect(e.state.active == nil)
    #expect(e.state.stats.skipped[.water] == 1)
    #expect(e.state.nextDue[.water] == at(28, 11, 0))
}

@Test func resumeFromAwayRestartsTheLadderAtTheFirstAttempt() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    e.resumeFromAway(now: at(28, 11, 45))
    #expect(e.plan(now: at(28, 11, 45))?.attempt == 0)
}

@Test func pushinessChangesTheLadderForTheActiveReminder() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    var s = e.settings
    s.pushiness = .max
    e.applySettings(s, now: at(28, 9, 46))
    #expect(e.plan(now: at(28, 9, 48))?.attempt == 1)   // max retries every 3 min
}

@Test func newDayResetsStatsAndRefillsHydration() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    e.complete(now: at(28, 9, 46))
    e.tick(now: at(28, 17, 59), hushed: false)
    #expect(e.state.hydration.level < 0.5)
    e.tick(now: at(29, 8), hushed: false)
    #expect(e.state.stats.day == "2026-09-29")
    #expect(e.state.stats.done.isEmpty)
    #expect(e.state.hydration.level == 1)
    #expect(e.state.nextDue[.water] == at(29, 9, 45))
}

@Test func reminderDueAtWindowEndRollsToNextDay() {
    var s = settings(.water)
    s.habits[.water]!.schedule = .atTimes([t(18)])
    var e = ReminderEngine(settings: s, state: nil, now: at(28, 9), calendar: cal)
    e.tick(now: at(28, 18), hushed: false)
    #expect(e.state.active == nil)
}

@Test func nearlyEvaporatedCountsEachDipOnce() {
    var e = engine(.water)
    e.tick(now: at(28, 10, 25), hushed: true)   // drained to ~0.04
    e.tick(now: at(28, 10, 26), hushed: true)
    #expect(e.state.stats.nearlyEvaporated == 1)
    e.logDone(.water, now: at(28, 10, 27))
    e.tick(now: at(28, 10, 28), hushed: true)   // back above 10%
    e.tick(now: at(28, 11, 25), hushed: true)   // dips again
    #expect(e.state.stats.nearlyEvaporated == 2)
}

@Test func disablingActiveHabitClearsIt() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    var s = e.settings
    s.habits[.water]!.enabled = false
    e.applySettings(s, now: at(28, 9, 46))
    #expect(e.state.active == nil)
    #expect(e.state.nextDue[.water] == nil)
}

@Test func enablingHabitSchedulesItFromNow() {
    var e = engine()
    var s = e.settings
    s.habits[.posture]!.enabled = true
    e.applySettings(s, now: at(28, 11))
    #expect(e.state.nextDue[.posture] == at(28, 11, 30))
}

@Test func changingNudgesUpdatesTheActiveReminder() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: false)
    var s = e.settings
    s.habits[.water]!.nudges = [.menuWiggle]
    e.applySettings(s, now: at(28, 9, 46))
    #expect(e.plan(now: at(28, 9, 46))?.types == [.menuWiggle])
}

@Test func engineStateRoundTripsThroughJSON() throws {
    var e = engine(.water, .eyes)
    e.tick(now: at(28, 9, 45), hushed: false)
    let data = try JSONEncoder().encode(e.state)
    #expect(try JSONDecoder().decode(EngineState.self, from: data) == e.state)
}

@Test func startNowShowsTheHabitImmediatelyEvenOutsideItsHours() {
    var e = engine(.eyes, now: at(28, 23))          // 11 pm, window is 9–18
    let original = e.state.nextDue[.eyes]
    e.startNow(.eyes, now: at(28, 23))
    #expect(e.state.active?.kind == .eyes)
    e.tick(now: at(28, 23, 0, 1), hushed: false)
    e.tick(now: at(28, 23, 0, 30), hushed: false)
    #expect(e.state.active?.kind == .eyes)             // not dropped for being out of hours
    #expect(e.state.nextDue[.eyes] == original)        // its schedule wasn't touched
    e.complete(now: at(28, 23, 1))
    #expect(e.state.active == nil)
    #expect(e.state.stats.done[.eyes] == 1)
    #expect(e.state.nextDue[.eyes] == at(29, 9, 20))   // back on schedule tomorrow
}

@Test func startNowDoesNothingWhenSomethingIsAlreadyActive() {
    var e = engine(.water, .eyes)
    e.tick(now: at(28, 9, 45), hushed: false)
    e.startNow(.eyes, now: at(28, 9, 46))
    #expect(e.state.active?.kind == .water)
}

@Test func activeReminderSavedByOlderBuildsStillLoads() throws {
    let json = #"{"kind":"water","firedAt":812287570.27}"#
    let a = try JSONDecoder().decode(ActiveReminder.self, from: Data(json.utf8))
    #expect(a.kind == .water)
    #expect(a.manual == false)
}

@Test func reminderOpenAtWindowEndIsDroppedAndNotRefiredEverySecond() {
    var s = settings(.water)
    s.habits[.water]!.schedule = .every(minutes: 5, anchor: .lastDone)
    var e = ReminderEngine(settings: s, state: nil, now: at(28, 17, 50), calendar: cal)
    e.tick(now: at(28, 17, 55), hushed: false)
    #expect(e.state.active?.kind == .water)
    e.tick(now: at(28, 18, 0, 1), hushed: false)
    #expect(e.state.active == nil)
    e.tick(now: at(28, 18, 0, 2), hushed: false)
    #expect(e.state.active == nil)
    #expect(e.state.queued.isEmpty)
}

@Test func endingHushGraceLetsRemindersFireImmediately() {
    var e = engine(.water)
    e.tick(now: at(28, 9, 45), hushed: true)
    e.tick(now: at(28, 9, 46), hushed: false)       // grace period starts
    e.clearHushGrace()
    e.tick(now: at(28, 9, 46, 1), hushed: false)
    #expect(e.state.active?.kind == .water)
}
