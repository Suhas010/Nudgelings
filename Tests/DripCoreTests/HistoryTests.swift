import Foundation
import Testing
@testable import DripCore

private func water(_ extra: HabitKind...) -> ReminderEngine {
    var s = Settings.initial
    s.habits[.water]!.enabled = true
    for k in extra { s.habits[k]!.enabled = true }
    return ReminderEngine(settings: s, state: nil, now: at(28, 9), calendar: cal)
}

@Test func finishedDaysAreArchivedWithTheirGoals() {
    var e = water()
    e.tick(now: at(28, 9, 45), hushed: false)
    e.complete(now: at(28, 9, 50))
    e.tick(now: at(29, 8), hushed: false)
    #expect(e.state.history.count == 1)
    #expect(e.state.history[0].day == "2026-09-28")
    #expect(e.state.history[0].done[.water] == 1)
    #expect(e.state.history[0].goals[.water] == 8)
}

@Test func historyKeepsAboutAYear() {
    var e = water()
    for d in 1...400 {
        e.tick(now: cal.date(byAdding: .day, value: d, to: at(28, 12))!, hushed: true)
    }
    #expect(e.state.history.count == ReminderEngine.historyDays)
    #expect(e.state.history.last?.day == "2027-11-01")   // newest kept, oldest dropped
}

@Test func longestWaitRemembersTheReminderLeftWaitingLongest() {
    var e = water(.eyes)
    e.tick(now: at(28, 9, 20), hushed: false)          // eyes fires
    e.complete(now: at(28, 9, 20, 30))                 // 30 s
    e.tick(now: at(28, 9, 45), hushed: false)          // water fires
    e.complete(now: at(28, 9, 53))                     // 8 min
    #expect(e.state.stats.longestWait == 8 * 60)
    #expect(e.state.stats.longestWaitKind == .water)
}

private func day(_ key: String, water: Int, goal: Int = 8) -> DayStats {
    var d = DayStats(day: key)
    d.done = [.water: water]
    d.goals = [.water: goal]
    return d
}

@Test func streakCountsConsecutiveGoodWorkdaysAndSkipsWeekends() {
    var s = Settings.initial
    s.habits[.water]!.enabled = true                   // Mon–Fri
    // Wed 23, Thu 24, Fri 25 good; Sat/Sun off; today Mon 28 in progress (not yet good)
    let history = [day("2026-09-22", water: 1), day("2026-09-23", water: 5), day("2026-09-24", water: 8),
                   day("2026-09-25", water: 4)]
    let today = day("2026-09-28", water: 1)
    let st = Streak.compute(history: history, today: today, settings: s, calendar: cal)
    #expect(st.current == 3)                            // today not good yet, but the streak isn't broken
    #expect(st.best == 3)
}

@Test func aGoodTodayExtendsTheStreakAndAMissedDayBreaksIt() {
    var s = Settings.initial
    s.habits[.water]!.enabled = true
    let history = [day("2026-09-21", water: 8), day("2026-09-22", water: 8), day("2026-09-23", water: 0),
                   day("2026-09-24", water: 6), day("2026-09-25", water: 6)]
    let st = Streak.compute(history: history, today: day("2026-09-28", water: 4), settings: s, calendar: cal)
    #expect(st.current == 3)                            // Thu, Fri, today
    #expect(st.best == 3)
}

@Test func stateSavedByOlderBuildsLoadsWithTodaysProgress() throws {
    let old = #"{"lastDone":[],"nextDue":[],"queued":[],"hydration":{"level":0.5,"updatedAt":0},"stats":{"day":"2026-09-28","done":["water",3],"skipped":[],"snoozes":1,"nearlyEvaporated":0,"lowestLevel":0.4},"wasHushed":false,"wasBelow10":false}"#
    let st = try JSONDecoder().decode(EngineState.self, from: Data(old.utf8))
    #expect(st.stats.done[.water] == 3)
    #expect(st.history.isEmpty)
    #expect(st.stats.goals.isEmpty)
}

@Test func soundVolumeDefaultsAndRoundTrips() throws {
    var s = Settings.initial
    #expect(s.soundVolume == 0.6)
    s.soundVolume = 0.2
    #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s)).soundVolume == 0.2)
}
