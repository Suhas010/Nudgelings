import Foundation
import SwiftUI
import DripCore

/// What's on screen right now for the active reminder (or a preview of one).
struct Presentation: Equatable {
    var kind: HabitKind
    var types: [NudgeType]
    var attempt: Int
    /// Inside the attempt's show window (otherwise only the menu-bar character hops).
    var showing: Bool
    /// When this attempt started — drives fade-ins, walk-across timing and sound cues.
    var attemptStartedAt: Date
    var isPreview: Bool

    func has(_ t: NudgeType) -> Bool { showing && types.contains(t) }
    var blocksScreen: Bool { showing && types.contains(where: \.blocksScreen) }
    /// On-screen nudges get a corner toast so there's always something to click.
    var wantsToast: Bool {
        showing && !blocksScreen && types.contains { [.toast, .menuShow, .walkAcross, .cursorTrail, .dim, .gag].contains($0) }
    }
}

/// Owns the engine, drives it once a second, and turns its state into what the UI shows.
@MainActor
final class AppModel: ObservableObject {
    struct Preview: Equatable {
        var kind: HabitKind
        var types: [NudgeType]
        var startedAt: Date
    }

    static let previewSeconds: TimeInterval = 25

    @Published private(set) var settings: DripCore.Settings
    @Published private(set) var state: EngineState
    @Published private(set) var presentation: Presentation?
    @Published private(set) var preview: Preview?
    @Published private(set) var celebration: Celebration?
    @Published private(set) var hushReason: HushReason?
    @Published private(set) var gagStartedAt: Date?
    @Published var line: String

    /// Called after every change so AppKit-side presenters can sync.
    var onUpdate: (() -> Void)?

    let store: Store
    let hush = HushDetector()
    let notifier = Notifier()
    let sound = SoundPlayer()
    private var engine: ReminderEngine
    private var timer: Timer?
    private var away = false
    private var notifiedFor: Date?
    private var soundedAttempt: String?
    private var lastSaved: EngineState?

    init(store: Store = AppModel.defaultStore()) {
        self.store = store
        let settings = store.loadSettings()
        let engine = ReminderEngine(settings: settings, state: store.loadState(), now: Date(), calendar: Self.calendar)
        self.engine = engine
        self.settings = settings
        self.state = engine.state
        self.line = Lines.pick(.mood(engine.state.hydration.mood))
        notifier.onAction = { [weak self] action, kind in
            Task { @MainActor in
                // A stale banner must not complete whichever habit happens to be active now.
                guard let self, self.activeKind == kind else { return }
                switch action {
                case .done: self.done()
                case .snooze: self.snooze()
                }
            }
        }
    }

    nonisolated static func defaultStore() -> Store {
        for legacy in Store.legacyDirectories { Store.migrate(from: legacy, to: Store.defaultDirectory) }
        return Store(directory: Store.defaultDirectory)
    }

    func start() {
        sound.volume = Float(settings.soundVolume)
        notifier.setup()
        if settings.habits.values.contains(where: { $0.enabled && $0.notify }) { notifier.requestAuthorization() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    // MARK: Derived

    var activeKind: HabitKind? { preview?.kind ?? state.active?.kind }
    var mood: Mood { state.hydration.mood }
    var waterEnabled: Bool { settings.config(.water).enabled }
    var hasReminder: Bool { activeKind != nil }
    var isPaused: Bool { settings.isPaused(at: Date()) }
    var dayProgress: Double { DayProgress.fraction(settings: settings, stats: state.stats) }

    /// Gregorian with the user's time zone, so day keys and weekdays mean the same thing everywhere.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    // MARK: Loop

    func tick() {
        let now = Date()
        // Camera/mic/window polling only matters when something could fire soon.
        let s = engine.state
        if s.active != nil || !s.queued.isEmpty || hush.reason != nil
            || s.nextDue.values.contains(where: { $0 < now + 10 }) {
            hush.poll(enabled: settings.autoHush)
        }
        let reason: HushReason? = away ? .away : settings.isPaused(at: now) ? .paused : hush.reason
        if reason != hushReason { hushReason = reason }

        let before = engine.state
        engine.tick(now: now, hushed: reason != nil)
        let after = engine.state

        if after.active != before.active, let a = after.active, a.firedAt == now {
            gagStartedAt = nil
            notifiedFor = nil
            line = before.hushEndedAt != nil && a.kind == .water
                ? Lines.pick(.hushOver) : Lines.pick(.reminder(a.kind), avoiding: line)
        } else if after.active == nil, before.active != nil, preview == nil {
            line = Lines.pick(.mood(after.hydration.mood))
        }

        if let p = preview, now.timeIntervalSince(p.startedAt) > Self.previewSeconds { preview = nil; gagStartedAt = nil }
        let attemptBefore = presentation?.attemptStartedAt
        let wasShowing = presentation?.showing == true
        publish(now)
        // A new retry starts its own countdown; a nudge that just got hidden (hush, pause, lock) goes quiet.
        if presentation?.attemptStartedAt != attemptBefore { gagStartedAt = nil }
        if wasShowing, presentation?.showing != true { sound.stop() }
        playSoundIfNeeded()
        autoCompleteTimedNudges(now)
        postNotificationIfNeeded()
        onUpdate?()
    }

    /// Hydration drifts every tick; compare at the precision anything shows (whole percent)
    /// so SwiftUI re-renders and disk writes only happen on real changes.
    private static func meaningful(_ s: EngineState) -> EngineState {
        var m = s
        m.hydration = HydrationState(level: (s.hydration.level * 100).rounded() / 100, updatedAt: .distantPast)
        m.stats.lowestLevel = (s.stats.lowestLevel * 100).rounded() / 100
        return m
    }

    private func publish(_ now: Date) {
        let s = engine.state
        if Self.meaningful(s) != Self.meaningful(state) { state = s }
        let p = currentPresentation(now)
        if p != presentation { presentation = p }
        if lastSaved.map(Self.meaningful) != Self.meaningful(s) { save() }
    }

    func save() {
        try? store.save(engine.state)
        lastSaved = engine.state
    }

    private func currentPresentation(_ now: Date) -> Presentation? {
        if let p = preview {
            return Presentation(kind: p.kind, types: p.types, attempt: 0, showing: true,
                                attemptStartedAt: p.startedAt, isPreview: true)
        }
        guard let a = engine.state.active, let plan = engine.plan(now: now) else { return nil }
        let c = settings.config(a.kind)
        let retry = Nudging.retrySeconds(retryMinutes: c.retryMinutes, pushiness: settings.pushiness)
        return Presentation(kind: a.kind, types: plan.types, attempt: plan.attempt, showing: plan.showing,
                            attemptStartedAt: a.firedAt + Double(plan.attempt) * retry, isPreview: false)
    }

    /// Once per attempt: play the character's sound cue.
    private func playSoundIfNeeded() {
        guard let p = presentation, p.showing else { return }
        let key = "\(p.kind.rawValue)-\(p.attemptStartedAt.timeIntervalSinceReferenceDate)"
        guard soundedAttempt != key else { return }
        soundedAttempt = key
        let cue = settings.config(p.kind).sound
        if p.types.contains(.takeover) && p.kind == .water {
            sound.play(cue, seconds: 20)
        } else if p.types.contains(.sound) {
            sound.play(cue, seconds: 8)
        }
    }

    /// Timed nudges finish themselves: Peep's dim/spotlight after 20s, the stretch gag after its countdown.
    private func autoCompleteTimedNudges(_ now: Date) {
        guard let p = presentation, p.showing else { return }
        if p.kind == .eyes, p.has(.dim) || p.has(.takeover),
           now.timeIntervalSince(p.attemptStartedAt) >= (HabitKind.eyes.gagSeconds ?? 20) + 1.5 {
            done()
            return
        }
        if p.has(.gag), let start = gagStartedAt, let length = p.kind.gagSeconds {
            let tail = p.kind == .eyes ? HabitKind.wiperSeconds + 0.1 : 0
            if now.timeIntervalSince(start) >= length + tail { done() }
        }
    }

    /// One banner per reminder, as soon as it fires, if the habit has "also notify" on.
    private func postNotificationIfNeeded() {
        guard preview == nil, let a = engine.state.active, notifiedFor != a.firedAt,
              settings.config(a.kind).notify else { return }
        notifiedFor = a.firedAt
        notifier.post(kind: a.kind, body: line)
    }

    // MARK: Actions

    func done() {
        let now = Date()
        guard let kind = activeKind else { return }
        notifier.clear(kind: kind)
        sound.stop()
        if preview != nil { preview = nil } else { engine.complete(now: now) }
        celebrate(kind)
        line = Lines.pick(.done(kind), avoiding: line)
        gagStartedAt = nil
        sync(now)
    }

    func snooze() {
        let now = Date()
        guard let kind = activeKind else { return }
        notifier.clear(kind: kind)
        sound.stop()
        if preview != nil { preview = nil } else { engine.snooze(now: now) }
        line = Lines.pick(.snoozed(kind), avoiding: line)
        gagStartedAt = nil
        sync(now)
    }

    func skip() {
        let now = Date()
        if let kind = activeKind { notifier.clear(kind: kind) }
        sound.stop()
        if preview != nil { preview = nil } else { engine.skip(now: now) }
        line = Lines.pick(.mood(mood))
        gagStartedAt = nil
        sync(now)
    }

    func startGagTimer() { gagStartedAt = Date(); onUpdate?() }

    func logDone(_ kind: HabitKind) {
        let now = Date()
        if activeKind == kind { done(); return }
        engine.logDone(kind, now: now)
        celebrate(kind)
        line = Lines.pick(.done(kind), avoiding: line)
        sync(now)
    }

    /// Show a habit's nudges right now, without touching its schedule.
    func previewNudges(_ kind: HabitKind, types: [NudgeType]? = nil) {
        let types = types ?? settings.config(kind).nudges
        preview = Preview(kind: kind, types: types, startedAt: Date())
        gagStartedAt = nil
        soundedAttempt = nil
        line = Lines.pick(.reminder(kind), avoiding: line)
        tick()
    }

    /// Set by the app delegate: shows the welcome tour again.
    var replayOnboarding: (() -> Void)?

    var streak: (current: Int, best: Int) {
        Streak.compute(history: state.history, today: state.stats, settings: settings, calendar: Self.calendar)
    }

    /// This week, Monday first: each day's stats (nil for days not reached yet or never recorded).
    var week: [(date: Date, stats: DayStats?)] {
        let cal = Self.calendar
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)        // 1 = Sunday
        let monday = cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        let byDay = Dictionary(state.history.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            let key = ReminderEngine.dayKey(d, cal)
            return (d, key == state.stats.day ? state.stats : (d < today ? byDay[key] : nil))
        }
    }

    func weekTotal(_ kind: HabitKind) -> Int { week.reduce(0) { $0 + ($1.stats?.done[kind] ?? 0) } }

    /// The enabled habit due soonest, and when.
    var nextUp: (kind: HabitKind, at: Date)? {
        settings.enabledKinds.compactMap { k in state.nextDue[k].map { (k, $0) } }.min { $0.1 < $1.1 }
    }

    /// "Start ⟨next⟩ now": the soonest habit's nudge shows up right away. Returns who.
    @discardableResult
    func startNextNow() -> HabitKind? {
        guard !hasReminder, let kind = nextUp?.kind else { return nil }
        engine.startNow(kind, now: Date())
        line = Lines.pick(.reminder(kind), avoiding: line)
        notifiedFor = nil
        tick()
        return kind
    }

    func pause(hours: Double) { pause(until: Date() + hours * 3600) }

    /// Pause until the crew's earliest start tomorrow.
    func pauseUntilTomorrow() {
        let cal = Self.calendar
        let tomorrow = cal.startOfDay(for: Date()).addingTimeInterval(86_400)
        let earliest = settings.enabledKinds.map { settings.config($0).window.start }.min() ?? ClockTime(hour: 9, minute: 0)
        pause(until: tomorrow + Double(earliest.minutesSinceMidnight * 60))
    }

    private func pause(until date: Date) {
        var s = settings
        s.pausedUntil = date
        if activeKind != nil { skipQuietly() }
        update(s)
    }

    /// "11:55 PM" today, "tomorrow 9:00 AM" otherwise.
    var pausedUntilText: String? {
        guard isPaused, let d = settings.pausedUntil else { return nil }
        let t = d.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(d) ? t : "tomorrow \(t)"
    }

    func resume() {
        var s = settings
        s.pausedUntil = nil
        update(s)
        engine.clearHushGrace()
        engine.resumeFromAway(now: Date())
        tick()
    }

    /// Clears an on-screen reminder without the usual "skip" line (used when pausing).
    private func skipQuietly() {
        let now = Date()
        if let kind = activeKind { notifier.clear(kind: kind) }
        sound.stop()
        if preview != nil { preview = nil } else { engine.snooze(now: now) }
        gagStartedAt = nil
    }

    func update(_ new: DripCore.Settings) {
        let now = Date()
        if HabitKind.allCases.contains(where: { new.config($0).enabled && new.config($0).notify
            && !(settings.config($0).enabled && settings.config($0).notify) }) {
            notifier.requestAuthorization()
        }
        engine.applySettings(new, now: now)
        settings = new
        sound.volume = Float(new.soundVolume)
        try? store.save(new)
        sync(now)
    }

    func updateHabit(_ kind: HabitKind, _ change: (inout HabitConfig) -> Void) {
        var s = settings
        var c = s.config(kind)
        change(&c)
        s.habits[kind] = c
        update(s)
    }

    func setAway(_ isAway: Bool, now: Date = Date()) {
        guard isAway != away else { return }
        away = isAway
        if !isAway { engine.resumeFromAway(now: now) }
        tick()
        if isAway { save() }
    }

    private func celebrate(_ kind: HabitKind) {
        let c = Celebration(kind: kind, start: Date())
        celebration = c
        DispatchQueue.main.asyncAfter(deadline: .now() + c.duration) { [weak self] in
            guard let self, self.celebration == c else { return }
            self.celebration = nil
            self.onUpdate?()
        }
    }

    private func sync(_ now: Date) {
        state = engine.state
        presentation = currentPresentation(now)
        save()
        onUpdate?()
    }
}
