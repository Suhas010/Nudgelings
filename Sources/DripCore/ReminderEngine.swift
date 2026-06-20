import Foundation

public struct ActiveReminder: Codable, Equatable, Sendable {
    public var kind: HabitKind
    public var firedAt: Date
    /// Started by the user ("Start Peep now"): shown regardless of the habit's active hours.
    public var manual = false

    public init(kind: HabitKind, firedAt: Date, manual: Bool = false) {
        self.kind = kind; self.firedAt = firedAt; self.manual = manual
    }

    private enum CodingKeys: String, CodingKey { case kind, firedAt, manual }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(HabitKind.self, forKey: .kind), firedAt: try c.decode(Date.self, forKey: .firedAt),
                  manual: try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false)
    }
}

public struct DayStats: Codable, Equatable, Sendable {
    /// yyyy-MM-dd in the engine's calendar.
    public var day: String
    public var done: [HabitKind: Int] = [:]
    public var skipped: [HabitKind: Int] = [:]
    public var snoozes = 0
    public var nearlyEvaporated = 0
    public var lowestLevel = 1.0
    /// The day's goals for the habits on shift (so old days keep the goals they had).
    public var goals: [HabitKind: Int] = [:]
    /// The reminder left waiting longest before it was done ("Peep waited 42 minutes…").
    public var longestWait: TimeInterval = 0
    public var longestWaitKind: HabitKind?

    public init(day: String) { self.day = day }

    /// Mean of done/goal (each capped at 100%) over the day's goals; 0 when there were none.
    public var fraction: Double {
        guard !goals.isEmpty else { return 0 }
        return goals.reduce(0.0) { $0 + min(1, Double(done[$1.key] ?? 0) / Double(max(1, $1.value))) } / Double(goals.count)
    }

    private enum CodingKeys: String, CodingKey {
        case day, done, skipped, snoozes, nearlyEvaporated, lowestLevel, goals, longestWait, longestWaitKind
    }

    /// Newer fields are optional so older saved days still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        done = try c.decodeIfPresent([HabitKind: Int].self, forKey: .done) ?? [:]
        skipped = try c.decodeIfPresent([HabitKind: Int].self, forKey: .skipped) ?? [:]
        snoozes = try c.decodeIfPresent(Int.self, forKey: .snoozes) ?? 0
        nearlyEvaporated = try c.decodeIfPresent(Int.self, forKey: .nearlyEvaporated) ?? 0
        lowestLevel = try c.decodeIfPresent(Double.self, forKey: .lowestLevel) ?? 1
        goals = try c.decodeIfPresent([HabitKind: Int].self, forKey: .goals) ?? [:]
        longestWait = try c.decodeIfPresent(TimeInterval.self, forKey: .longestWait) ?? 0
        longestWaitKind = try c.decodeIfPresent(HabitKind.self, forKey: .longestWaitKind)
    }
}

public struct EngineState: Codable, Equatable, Sendable {
    public var lastDone: [HabitKind: Date] = [:]
    public var nextDue: [HabitKind: Date] = [:]
    public var active: ActiveReminder?
    public var queued: [HabitKind] = []
    public var hydration: HydrationState
    public var stats: DayStats
    public var wasHushed = false
    public var hushEndedAt: Date?
    public var wasBelow10 = false
    /// Finished days, oldest first (capped at `ReminderEngine.historyDays`).
    public var history: [DayStats] = []

    public init(hydration: HydrationState, stats: DayStats) { self.hydration = hydration; self.stats = stats }

    private enum CodingKeys: String, CodingKey {
        case lastDone, nextDue, active, queued, hydration, stats, wasHushed, hushEndedAt, wasBelow10, history
    }

    /// Newer fields are optional so a state file from an older build keeps today's progress.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hydration = try c.decode(HydrationState.self, forKey: .hydration)
        stats = try c.decode(DayStats.self, forKey: .stats)
        lastDone = try c.decodeIfPresent([HabitKind: Date].self, forKey: .lastDone) ?? [:]
        nextDue = try c.decodeIfPresent([HabitKind: Date].self, forKey: .nextDue) ?? [:]
        active = try c.decodeIfPresent(ActiveReminder.self, forKey: .active)
        queued = try c.decodeIfPresent([HabitKind].self, forKey: .queued) ?? []
        wasHushed = try c.decodeIfPresent(Bool.self, forKey: .wasHushed) ?? false
        hushEndedAt = try c.decodeIfPresent(Date.self, forKey: .hushEndedAt)
        wasBelow10 = try c.decodeIfPresent(Bool.self, forKey: .wasBelow10) ?? false
        history = try c.decodeIfPresent([DayStats].self, forKey: .history) ?? []
    }
}

/// The reminder state machine. Pure: all time comes in through `now`.
///
///   nextDue ≤ now ──▶ queued ──(not hushed, 2m after hush ends)──▶ active
///                                                                   │
///            complete / skip / gave up ──▶ reschedule    ◀─────────┤
///            snooze                    ──▶ now + 5m      ◀─────────┘
///   hush starts while active ──▶ back to front of queue (flood restarts gently)
public struct ReminderEngine: Sendable {
    public static let snoozeSeconds: TimeInterval = 300
    public static let hushResumeDelay: TimeInterval = 120
    public static let evaporationThreshold = 0.10
    public static let historyDays = 370

    public private(set) var settings: Settings
    public private(set) var state: EngineState
    public let calendar: Calendar

    public init(settings: Settings, state: EngineState?, now: Date, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
        self.state = state ?? EngineState(hydration: .full(at: now), stats: DayStats(day: Self.dayKey(now, calendar)))
        if self.state.stats.goals.isEmpty { self.state.stats.goals = currentGoals }
        rescheduleAll(now: now)
    }

    // MARK: Ticking

    public mutating func tick(now: Date, hushed: Bool) {
        rollDayIfNeeded(now: now)
        updateHydration(now: now)
        dropOutOfWindow(now: now)

        if hushed && !state.wasHushed {
            state.wasHushed = true
            state.hushEndedAt = nil
            if let a = state.active {
                state.active = nil
                state.queued.removeAll { $0 == a.kind }
                state.queued.insert(a.kind, at: 0)
            }
        } else if !hushed && state.wasHushed {
            state.wasHushed = false
            state.hushEndedAt = now
        }

        for kind in settings.enabledKinds {
            // Outside the habit's hours a past-due entry waits (it's rescheduled below), never re-queues.
            guard let due = state.nextDue[kind], due <= now,
                  settings.config(kind).window.contains(now, calendar: calendar),
                  state.active?.kind != kind, !state.queued.contains(kind) else { continue }
            state.queued.append(kind)
        }
        let rank = HabitKind.allCases
        state.queued.sort { rank.firstIndex(of: $0)! < rank.firstIndex(of: $1)! }

        guard !hushed else { return }
        if let ended = state.hushEndedAt {
            guard now.timeIntervalSince(ended) >= Self.hushResumeDelay else { return }
            state.hushEndedAt = nil
        }
        // Ignored through every retry: the character lets it go (counted as a skip, no grudges).
        if plan(now: now)?.gaveUp == true { skip(now: now) }

        if state.active == nil, !state.queued.isEmpty {
            let kind = state.queued.removeFirst()
            state.active = ActiveReminder(kind: kind, firedAt: now)
        }
    }

    public func plan(now: Date) -> NudgePlan? {
        guard let a = state.active else { return nil }
        let c = settings.config(a.kind)
        return Nudging.plan(nudges: c.nudges, retryMinutes: c.retryMinutes, pushiness: settings.pushiness,
                            elapsed: now.timeIntervalSince(a.firedAt))
    }

    /// After sleep/lock the timer didn't run; restart the active reminder from its calmest stage.
    public mutating func resumeFromAway(now: Date) {
        state.active?.firedAt = now
    }

    // MARK: User actions

    public mutating func complete(now: Date) {
        guard let a = state.active else { return }
        let waited = now.timeIntervalSince(a.firedAt)
        if waited > state.stats.longestWait {
            state.stats.longestWait = waited
            state.stats.longestWaitKind = a.kind
        }
        logDone(a.kind, now: now)
    }

    /// Records a habit as done, whether or not it was the active reminder (e.g. "I drank" from the menu).
    public mutating func logDone(_ kind: HabitKind, now: Date) {
        if kind == .water {
            state.hydration = state.hydration.drained(to: now, waterIntervalMinutes: waterInterval).drinking(at: now)
        }
        state.stats.done[kind, default: 0] += 1
        state.lastDone[kind] = now
        state.nextDue[kind] = Scheduler.nextDue(settings.config(kind), lastDone: now, after: now, calendar: calendar)
        clear(kind)
    }

    /// "Start Peep now": show this habit's nudge immediately, whatever the hour.
    /// Its schedule is untouched until it's done, snoozed or skipped.
    public mutating func startNow(_ kind: HabitKind, now: Date) {
        guard state.active == nil else { return }
        state.queued.removeAll { $0 == kind }
        state.active = ActiveReminder(kind: kind, firedAt: now, manual: true)
    }

    /// Resume / take a break now: skip the post-hush grace so reminders can fire straight away.
    public mutating func clearHushGrace() { state.hushEndedAt = nil }

    public mutating func snooze(now: Date) {
        guard let a = state.active else { return }
        state.stats.snoozes += 1
        state.nextDue[a.kind] = now + Self.snoozeSeconds
        clear(a.kind)
    }

    public mutating func skip(now: Date) {
        guard let a = state.active else { return }
        state.stats.skipped[a.kind, default: 0] += 1
        state.nextDue[a.kind] = Scheduler.nextDue(settings.config(a.kind), lastDone: now, after: now, calendar: calendar)
        clear(a.kind)
    }

    public mutating func applySettings(_ new: Settings, now: Date) {
        let old = settings
        settings = new
        state.stats.goals = currentGoals
        for kind in HabitKind.allCases where old.config(kind) != new.config(kind) {
            let c = new.config(kind)
            if !c.enabled {
                state.nextDue[kind] = nil
                clear(kind)
                continue
            }
            let scheduleChanged = old.config(kind).schedule != c.schedule
                || old.config(kind).window != c.window || !old.config(kind).enabled
            if scheduleChanged {
                // A freshly enabled habit counts from now, not from a stale lastDone.
                let last = old.config(kind).enabled ? state.lastDone[kind] : nil
                state.nextDue[kind] = Scheduler.nextDue(c, lastDone: last, after: now, calendar: calendar)
            }
        }
    }

    // MARK: Helpers

    public var waterInterval: Int {
        if case let .every(minutes, _) = settings.config(.water).schedule { return minutes }
        return 60
    }

    public static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private mutating func clear(_ kind: HabitKind) {
        if state.active?.kind == kind { state.active = nil }
        state.queued.removeAll { $0 == kind }
    }

    private mutating func rescheduleAll(now: Date) {
        for kind in HabitKind.allCases {
            let c = settings.config(kind)
            state.nextDue[kind] = c.enabled
                ? Scheduler.nextDue(c, lastDone: state.lastDone[kind], after: now, calendar: calendar)
                : nil
        }
    }

    /// Goals of the habits currently on shift.
    var currentGoals: [HabitKind: Int] {
        Dictionary(uniqueKeysWithValues: settings.enabledKinds.map { ($0, settings.config($0).goal) })
    }

    private mutating func rollDayIfNeeded(now: Date) {
        let key = Self.dayKey(now, calendar)
        guard state.stats.day != key else { return }
        state.history.append(state.stats)
        if state.history.count > Self.historyDays { state.history.removeFirst(state.history.count - Self.historyDays) }
        state.stats = DayStats(day: key)
        state.stats.goals = currentGoals
        state.hydration = .full(at: now)
        state.wasBelow10 = false
        state.active = nil
        state.queued = []
        rescheduleAll(now: now)
    }

    private mutating func updateHydration(now: Date) {
        let water = settings.config(.water)
        guard water.enabled, water.window.contains(now, calendar: calendar) else {
            state.hydration.updatedAt = max(state.hydration.updatedAt, now)
            return
        }
        state.hydration = state.hydration.drained(to: now, waterIntervalMinutes: waterInterval)
        let level = state.hydration.level
        state.stats.lowestLevel = min(state.stats.lowestLevel, level)
        if level < Self.evaporationThreshold {
            if !state.wasBelow10 { state.stats.nearlyEvaporated += 1 }
            state.wasBelow10 = true
        } else {
            state.wasBelow10 = false
        }
    }

    /// Reminders never linger outside their habit's active hours (no fish at midnight);
    /// a dropped one is rescheduled into the next window.
    private mutating func dropOutOfWindow(now: Date) {
        if let a = state.active, !a.manual, !settings.config(a.kind).window.contains(now, calendar: calendar) {
            state.active = nil
            state.nextDue[a.kind] = Scheduler.nextDue(settings.config(a.kind), lastDone: state.lastDone[a.kind],
                                                      after: now, calendar: calendar)
        }
        let s = settings, cal = calendar
        state.queued.removeAll { !s.config($0).window.contains(now, calendar: cal) }
    }
}
