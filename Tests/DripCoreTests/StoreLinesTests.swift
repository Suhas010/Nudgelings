import Foundation
import Testing
@testable import DripCore

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("drip-\(UUID().uuidString)")
    return u
}

@Test func settingsRoundTripOnDisk() throws {
    let store = Store(directory: tempDir())
    var s = Settings.initial
    s.onboarded = true
    s.habits[.walk]!.enabled = true
    try store.save(s)
    #expect(store.loadSettings() == s)
}

@Test func missingFilesFallBackToDefaults() {
    let store = Store(directory: tempDir())
    #expect(store.loadSettings() == .initial)
    #expect(store.loadState() == nil)
}

@Test func corruptSettingsFallBackToDefaults() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{not json".utf8).write(to: dir.appendingPathComponent("settings.json"))
    #expect(Store(directory: dir).loadSettings() == .initial)
}

@Test func stateRoundTripOnDisk() throws {
    let store = Store(directory: tempDir())
    let e = ReminderEngine(settings: .initial, state: nil, now: at(28, 9), calendar: cal)
    try store.save(e.state)
    #expect(store.loadState() == e.state)
}

private var allContexts: [LineContext] {
    HabitKind.allCases.flatMap { [LineContext.reminder($0), .snoozed($0), .done($0)] }
        + Mood.allCases.flatMap { [LineContext.mood($0), .shareHeadline($0)] }
        + [.hushOver]
}

@Test func everyContextHasEnoughShortLines() {
    for c in allContexts {
        let lines = Lines.all(c)
        #expect(lines.count >= 5, "\(c) has \(lines.count)")
        for l in lines { #expect(l.count <= 70, "too long: \(l)") }
    }
    for m in Mood.allCases { #expect(Lines.all(.mood(m)).count >= 10) }
    #expect(Lines.all(.reminder(.water)).count >= 10)
}

@Test func pickNeverRepeatsTheLineToAvoid() {
    var rng = SystemRandomNumberGenerator()
    let avoid = Lines.all(.reminder(.water))[0]
    for _ in 0..<200 {
        #expect(Lines.pick(.reminder(.water), avoiding: avoid, using: &rng) != avoid)
    }
}

@Test func migratesLegacyFolderWhenNewOneIsMissing() throws {
    let old = tempDir(), new = tempDir()
    var s = Settings.initial
    s.onboarded = true
    try Store(directory: old).save(s)
    Store.migrate(from: old, to: new)
    #expect(Store(directory: new).loadSettings() == s)
}

@Test func migrationNeverOverwritesExistingData() throws {
    let old = tempDir(), new = tempDir()
    var legacy = Settings.initial
    legacy.onboarded = true
    try Store(directory: old).save(legacy)
    try Store(directory: new).save(Settings.initial)
    Store.migrate(from: old, to: new)
    #expect(Store(directory: new).loadSettings() == .initial)
}
