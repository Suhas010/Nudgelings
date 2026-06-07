import Foundation
import Testing
@testable import DripCore

private func water(_ schedule: Schedule? = nil, enabled: Bool = true) -> HabitConfig {
    var c = HabitConfig.defaults(for: .water)
    c.enabled = enabled
    if let schedule { c.schedule = schedule }
    return c
}

@Test func everyFromLastDoneAddsInterval() {
    #expect(Scheduler.nextDue(water(), lastDone: at(28, 10), after: at(28, 10), calendar: cal) == at(28, 10, 45))
}

@Test func freshlyEnabledHabitCountsFromNow() {
    #expect(Scheduler.nextDue(water(), lastDone: nil, after: at(28, 11), calendar: cal) == at(28, 11, 45))
}

@Test func candidatePastWindowEndRollsToNextDayStartPlusInterval() {
    #expect(Scheduler.nextDue(water(), lastDone: at(28, 17, 40), after: at(28, 17, 40), calendar: cal) == at(29, 9, 45))
}

@Test func dueExactlyAtWindowEndRollsOver() {
    // 17:15 + 45m = 18:00, which is outside (end is exclusive)
    #expect(Scheduler.nextDue(water(), lastDone: at(28, 17, 15), after: at(28, 17, 15), calendar: cal) == at(29, 9, 45))
}

@Test func lastDoneOnPreviousWorkdayCountsFromTodaysStart() {
    // Friday 10:00 drink; Monday 08:00 check → Monday 09:45
    #expect(Scheduler.nextDue(water(), lastDone: at(25, 10), after: at(28, 8), calendar: cal) == at(28, 9, 45))
}

@Test func overdueWithinTheSameWindowIsDueImmediately() {
    #expect(Scheduler.nextDue(water(), lastDone: at(28, 10), after: at(28, 11), calendar: cal) == at(28, 11))
}

@Test func clockAnchoredAlignsToMultiplesOfInterval() {
    let c = water(.every(minutes: 30, anchor: .clock))
    #expect(Scheduler.nextDue(c, lastDone: at(28, 10), after: at(28, 10, 7), calendar: cal) == at(28, 10, 30))
    #expect(Scheduler.nextDue(c, lastDone: nil, after: at(28, 10, 30), calendar: cal) == at(28, 11))
}

@Test func clockAnchoredSkipsToNextWindow() {
    let c = water(.every(minutes: 30, anchor: .clock))
    #expect(Scheduler.nextDue(c, lastDone: nil, after: at(28, 17, 45), calendar: cal) == at(29, 9))
}

@Test func atTimesPicksNextListedTime() {
    let c = water(.atTimes([t(15), t(10)]))
    #expect(Scheduler.nextDue(c, lastDone: nil, after: at(28, 11), calendar: cal) == at(28, 15))
    #expect(Scheduler.nextDue(c, lastDone: nil, after: at(28, 9), calendar: cal) == at(28, 10))
}

@Test func atTimesSkipsWeekend() {
    // Friday Oct 2 16:00 → Monday Oct 5 10:00
    let c = water(.atTimes([t(10), t(15)]))
    #expect(Scheduler.nextDue(c, lastDone: nil, after: at(2, 16, month: 10), calendar: cal) == at(5, 10, month: 10))
}

@Test func disabledOrEmptySchedulesNeverFire() {
    #expect(Scheduler.nextDue(water(enabled: false), lastDone: nil, after: at(28, 10), calendar: cal) == nil)
    #expect(Scheduler.nextDue(water(.atTimes([])), lastDone: nil, after: at(28, 10), calendar: cal) == nil)
    var noDays = water()
    noDays.window.weekdays = []
    #expect(Scheduler.nextDue(noDays, lastDone: nil, after: at(28, 10), calendar: cal) == nil)
}
