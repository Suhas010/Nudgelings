import Foundation

/// One habit, looked after by one character. Case order is the crew order everywhere.
public enum HabitKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case water, eyes, walk, stretch, posture, breathe, stand
    public var id: String { rawValue }

    public var character: String {
        switch self {
        case .water: "Drip"
        case .eyes: "Peep"
        case .walk: "Stompy"
        case .stretch: "Noodle"
        case .posture: "Sprout"
        case .breathe: "Puff"
        case .stand: "Pop"
        }
    }
}

public struct ClockTime: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }

    public var minutesSinceMidnight: Int { hour * 60 + minute }
    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutesSinceMidnight < b.minutesSinceMidnight }
}

/// What an "every N minutes" schedule counts from.
public enum Anchor: String, Codable, Sendable, CaseIterable {
    case lastDone, clock
}

public enum Schedule: Codable, Equatable, Sendable {
    case every(minutes: Int, anchor: Anchor)
    case atTimes([ClockTime])
}

/// Days + hours a habit is allowed to remind. `end` is exclusive.
public struct ActiveWindow: Codable, Equatable, Sendable {
    /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>
    public var start: ClockTime
    public var end: ClockTime

    public init(weekdays: Set<Int>, start: ClockTime, end: ClockTime) {
        self.weekdays = weekdays; self.start = start; self.end = end
    }

    public static let workdays = ActiveWindow(
        weekdays: [2, 3, 4, 5, 6],
        start: ClockTime(hour: 9, minute: 0),
        end: ClockTime(hour: 18, minute: 0)
    )

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, weekdays.contains(wd) else { return false }
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return m >= start.minutesSinceMidnight && m < end.minutesSinceMidnight
    }
}

/// The nudge ladder, quietest first. Ignored nudges retry one or more rungs higher.
public enum NudgeType: String, CaseIterable, Codable, Sendable, Identifiable {
    case menuWiggle, sound, toast, menuShow, walkAcross, cursorTrail, dim, gag, takeover, miniGame
    public var id: String { rawValue }

    public var rung: Int { Self.allCases.firstIndex(of: self)! }

    /// Covers the screen and takes clicks (everything else is click-through or tucked in a corner).
    public var blocksScreen: Bool { self == .takeover || self == .miniGame }
}

/// How hard the crew pushes when ignored.
public enum Pushiness: String, CaseIterable, Codable, Sendable, Identifiable {
    case gentle, nag, max
    public var id: String { rawValue }

    /// Multiplies each habit's "try again in N min".
    var retryFactor: Double {
        switch self {
        case .gentle: 1
        case .nag: 0.5
        case .max: 0.3
        }
    }
    var maxRetries: Int {
        switch self {
        case .gentle: 2
        case .nag: 3
        case .max: 4
        }
    }
    var rungsPerRetry: Int { self == .max ? 2 : 1 }
    /// The loudest rung escalation may reach, and how many ignores it takes to get there.
    var ceiling: NudgeType { self == .gentle ? .gag : .takeover }
    var ignoresBeforeTakeover: Int { self == .max ? 1 : 2 }
}

/// Ambient sound cue a character can play (generated at runtime; no audio files).
public enum SoundCue: String, CaseIterable, Codable, Sendable, Identifiable {
    case brook, rain, chime, birds, pop, breeze
    public var id: String { rawValue }
}

public struct HabitConfig: Codable, Equatable, Sendable {
    public static let maxNudges = 2

    public var kind: HabitKind
    public var enabled: Bool
    public var schedule: Schedule
    public var window: ActiveWindow
    /// One or two nudge types, in the order picked.
    public var nudges: [NudgeType]
    public var goal: Int
    public var retryMinutes: Int
    public var sound: SoundCue
    /// Also post a macOS notification when this habit's reminder fires.
    public var notify: Bool

    public init(kind: HabitKind, enabled: Bool, schedule: Schedule, window: ActiveWindow, nudges: [NudgeType],
                goal: Int, retryMinutes: Int = 10, sound: SoundCue, notify: Bool = true) {
        self.kind = kind; self.enabled = enabled; self.schedule = schedule; self.window = window
        self.nudges = nudges; self.goal = goal; self.retryMinutes = retryMinutes; self.sound = sound; self.notify = notify
    }

    public static func defaults(for kind: HabitKind) -> HabitConfig {
        let (minutes, nudges, goal, sound): (Int, [NudgeType], Int, SoundCue) = switch kind {
        case .water: (45, [.toast, .sound], 8, .brook)
        case .eyes: (20, [.dim], 12, .chime)
        case .walk: (90, [.walkAcross], 2, .birds)
        case .stretch: (60, [.miniGame], 6, .pop)
        case .posture: (30, [.menuWiggle], 8, .chime)
        case .breathe: (90, [.toast], 4, .breeze)
        case .stand: (60, [.toast], 6, .pop)
        }
        return HabitConfig(kind: kind, enabled: false, schedule: .every(minutes: minutes, anchor: .lastDone),
                           window: .workdays, nudges: nudges, goal: goal, sound: sound)
    }

    /// Pick or unpick a nudge type: at most two (the oldest pick drops off), never zero.
    public mutating func toggle(_ type: NudgeType) {
        if let i = nudges.firstIndex(of: type) {
            if nudges.count > 1 { nudges.remove(at: i) }
        } else {
            nudges.append(type)
            if nudges.count > Self.maxNudges { nudges.removeFirst() }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, enabled, schedule, window, nudges, goal, retryMinutes, sound, notify, style
    }

    /// Tolerates older files: missing fields take the character's defaults, and a pre-Nudgelings
    /// single `style` maps onto the nudge it most resembles.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(HabitKind.self, forKey: .kind)
        let d = HabitConfig.defaults(for: kind)
        let legacy = try c.decodeIfPresent(String.self, forKey: .style).map { style -> [NudgeType] in
            switch style {
            case "whisper": [.menuWiggle]
            case "notification": [.toast]
            case "menuBarWaves": [.menuShow]
            default: [.gag]   // signatureGag, flood
            }
        }
        self.init(kind: kind,
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled,
                  schedule: try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? d.schedule,
                  window: try c.decodeIfPresent(ActiveWindow.self, forKey: .window) ?? d.window,
                  nudges: try c.decodeIfPresent([NudgeType].self, forKey: .nudges) ?? legacy ?? d.nudges,
                  goal: try c.decodeIfPresent(Int.self, forKey: .goal) ?? d.goal,
                  retryMinutes: try c.decodeIfPresent(Int.self, forKey: .retryMinutes) ?? d.retryMinutes,
                  sound: try c.decodeIfPresent(SoundCue.self, forKey: .sound) ?? d.sound,
                  notify: try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(enabled, forKey: .enabled)
        try c.encode(schedule, forKey: .schedule); try c.encode(window, forKey: .window)
        try c.encode(nudges, forKey: .nudges); try c.encode(goal, forKey: .goal)
        try c.encode(retryMinutes, forKey: .retryMinutes); try c.encode(sound, forKey: .sound)
        try c.encode(notify, forKey: .notify)
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var habits: [HabitKind: HabitConfig]
    public var bottomWaterLine = true
    public var autoHush = true
    public var onboarded = false
    public var pushiness: Pushiness = .gentle
    /// "Pause 1h" — nothing fires until then.
    public var pausedUntil: Date?
    /// Sound cue loudness, 0…1.
    public var soundVolume = 0.6

    public init(habits: [HabitKind: HabitConfig]) { self.habits = habits }

    public static var initial: Settings {
        Settings(habits: Dictionary(uniqueKeysWithValues: HabitKind.allCases.map { ($0, .defaults(for: $0)) }))
    }

    public func config(_ kind: HabitKind) -> HabitConfig { habits[kind] ?? .defaults(for: kind) }

    public var enabledKinds: [HabitKind] { HabitKind.allCases.filter { config($0).enabled } }

    public func isPaused(at now: Date) -> Bool { pausedUntil.map { now < $0 } ?? false }

    private enum CodingKeys: String, CodingKey { case habits, bottomWaterLine, autoHush, onboarded, pushiness, pausedUntil, soundVolume }

    /// Older files lack newer fields and newer habits; fill both from defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = Settings.initial
        for (kind, config) in try c.decodeIfPresent([HabitKind: HabitConfig].self, forKey: .habits) ?? [:] {
            s.habits[kind] = config
        }
        s.bottomWaterLine = try c.decodeIfPresent(Bool.self, forKey: .bottomWaterLine) ?? s.bottomWaterLine
        s.autoHush = try c.decodeIfPresent(Bool.self, forKey: .autoHush) ?? s.autoHush
        s.onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? s.onboarded
        s.pushiness = try c.decodeIfPresent(Pushiness.self, forKey: .pushiness) ?? s.pushiness
        s.pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        s.soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? s.soundVolume
        self = s
    }
}

/// How much of today's goals are done.
public enum DayProgress {
    /// Mean of each enabled habit's done/goal, each capped at 100%.
    public static func fraction(settings: Settings, stats: DayStats) -> Double {
        let kinds = settings.enabledKinds
        guard !kinds.isEmpty else { return 0 }
        let sum = kinds.reduce(0.0) { acc, k in
            acc + min(1, Double(stats.done[k] ?? 0) / Double(max(1, settings.config(k).goal)))
        }
        return sum / Double(kinds.count)
    }

    /// Total completions today across enabled habits.
    public static func done(settings: Settings, stats: DayStats) -> Int {
        settings.enabledKinds.reduce(0) { $0 + (stats.done[$1] ?? 0) }
    }
}
