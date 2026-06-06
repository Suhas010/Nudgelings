import Foundation
import Testing
@testable import DripCore

@Test func sevenCharactersInCrewOrder() {
    #expect(HabitKind.allCases == [.water, .eyes, .walk, .stretch, .posture, .breathe, .stand])
    #expect(HabitKind.allCases.map(\.character) == ["Drip", "Peep", "Stompy", "Noodle", "Sprout", "Puff", "Pop"])
}

@Test func defaultsMatchTheCrewDesignAndStartDisabled() {
    let expected: [HabitKind: (minutes: Int, nudges: [NudgeType], goal: Int)] = [
        .water: (45, [.toast, .sound], 8),
        .eyes: (20, [.dim], 12),
        .walk: (90, [.walkAcross], 2),
        .stretch: (60, [.miniGame], 6),
        .posture: (30, [.menuWiggle], 8),
        .breathe: (90, [.toast], 4),
        .stand: (60, [.toast], 6),
    ]
    for kind in HabitKind.allCases {
        let c = HabitConfig.defaults(for: kind)
        let e = expected[kind]!
        #expect(c.enabled == false)
        #expect(c.schedule == .every(minutes: e.minutes, anchor: .lastDone))
        #expect(c.nudges == e.nudges, "\(kind)")
        #expect(c.goal == e.goal)
        #expect(c.window == .workdays)
        #expect(c.retryMinutes == 10)
        #expect(c.notify)
    }
}

@Test func nudgeLadderRunsFromWhisperToMiniGame() {
    #expect(NudgeType.allCases.first == .menuWiggle)
    #expect(NudgeType.allCases.last == .miniGame)
    #expect(NudgeType.takeover.blocksScreen && NudgeType.miniGame.blocksScreen)
    #expect(!NudgeType.toast.blocksScreen && !NudgeType.dim.blocksScreen)
}

@Test func choosingNudgesKeepsAtMostTwoAndNeverNone() {
    var c = HabitConfig.defaults(for: .water)          // [toast, sound]
    c.toggle(.walkAcross)
    #expect(c.nudges == [.sound, .walkAcross])         // oldest pick drops off
    c.toggle(.walkAcross)
    #expect(c.nudges == [.sound])
    c.toggle(.sound)
    #expect(c.nudges == [.sound])                      // can't remove the last one
}

@Test func workdaysWindowIsMonToFriNineToSix() {
    let w = ActiveWindow.workdays
    #expect(w.contains(at(28, 9), calendar: cal))
    #expect(w.contains(at(28, 17, 59), calendar: cal))
    #expect(!w.contains(at(28, 18), calendar: cal))
    #expect(!w.contains(at(28, 8, 59), calendar: cal))
    #expect(!w.contains(at(3, 12, month: 10), calendar: cal))
}

@Test func settingsRoundTripThroughJSON() throws {
    var s = Settings.initial
    s.habits[.eyes]!.enabled = true
    s.habits[.eyes]!.schedule = .atTimes([t(10), t(15, 30)])
    s.pushiness = .max
    s.pausedUntil = at(28, 11)
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
}

@Test func initialSettingsHaveEveryHabitOffGentleAndNotOnboarded() {
    let s = Settings.initial
    #expect(s.habits.count == 7)
    #expect(s.habits.values.allSatisfy { !$0.enabled })
    #expect(!s.onboarded)
    #expect(s.pushiness == .gentle)
    #expect(s.pausedUntil == nil)
}

/// A settings file written by the Sip Happens build (five habits, single `style`, no pushiness).
private let legacySettingsJSON = """
{"autoHush":true,"bottomWaterLine":false,"onboarded":true,"habits":[
 "water",{"kind":"water","enabled":true,"schedule":{"every":{"minutes":30,"anchor":"lastDone"}},
  "window":{"weekdays":[2,3,4,5,6],"start":{"hour":9,"minute":0},"end":{"hour":18,"minute":0}},
  "style":"flood","escalate":false,"notify":false},
 "eyes",{"kind":"eyes","enabled":true,"schedule":{"every":{"minutes":20,"anchor":"lastDone"}},
  "window":{"weekdays":[2,3,4,5,6],"start":{"hour":9,"minute":0},"end":{"hour":18,"minute":0}},
  "style":"whisper","escalate":true},
 "walk",{"kind":"walk","enabled":false,"schedule":{"atTimes":{"_0":[{"hour":11,"minute":30}]}},
  "window":{"weekdays":[2,3,4,5,6],"start":{"hour":9,"minute":0},"end":{"hour":18,"minute":0}},
  "style":"menuBarWaves","escalate":false}
]}
"""

@Test func legacySettingsLoadWithTheirChoicesMappedToNudges() throws {
    let s = try JSONDecoder().decode(Settings.self, from: Data(legacySettingsJSON.utf8))
    #expect(s.onboarded)
    #expect(!s.bottomWaterLine)
    #expect(s.pushiness == .gentle)
    #expect(s.config(.water).enabled)
    #expect(s.config(.water).schedule == .every(minutes: 30, anchor: .lastDone))
    #expect(s.config(.water).nudges == [.gag])
    #expect(s.config(.water).notify == false)
    #expect(s.config(.eyes).nudges == [.menuWiggle])
    #expect(s.config(.walk).nudges == [.menuShow])
    #expect(s.config(.walk).schedule == .atTimes([t(11, 30)]))
    // Habits the old build never knew about get their defaults.
    #expect(s.config(.breathe) == .defaults(for: .breathe))
    #expect(s.habits.count == 7)
}

@Test func dayProgressAveragesGoalsOfEnabledHabits() {
    var s = Settings.initial
    s.habits[.water]!.enabled = true     // goal 8
    s.habits[.walk]!.enabled = true      // goal 2
    var stats = DayStats(day: "2026-09-28")
    stats.done = [.water: 4, .walk: 5, .eyes: 9]   // eyes is off: ignored; walk capped at 100%
    #expect(abs(DayProgress.fraction(settings: s, stats: stats) - 0.75) < 0.0001)
    #expect(DayProgress.done(settings: s, stats: stats) == 9)
    #expect(DayProgress.fraction(settings: .initial, stats: stats) == 0)
}
