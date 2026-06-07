import Foundation

/// Decides when a habit should next remind.
///
///   every/lastDone:  lastDone ─N─▶ due     (overdue in same window → due now;
///                                            lastDone before today's window → window start + N)
///   every/clock:     next multiple of N since midnight, inside the window
///   atTimes:         next listed time on an active day, inside the window
public enum Scheduler {
    /// How far ahead we search before giving up (covers a long weekend).
    static let horizonDays = 8

    public static func nextDue(_ c: HabitConfig, lastDone: Date?, after: Date, calendar: Calendar) -> Date? {
        guard c.enabled else { return nil }
        switch c.schedule {
        case let .every(minutes, anchor):
            guard minutes > 0 else { return nil }
            return anchor == .clock
                ? clockAligned(c.window, minutes: minutes, after: after, calendar: calendar)
                : fromLastDone(c.window, minutes: minutes, lastDone: lastDone, after: after, calendar: calendar)
        case let .atTimes(times):
            return atTimes(c.window, times: times.sorted(), after: after, calendar: calendar)
        }
    }

    private static func fromLastDone(_ w: ActiveWindow, minutes: Int, lastDone: Date?, after: Date,
                                     calendar: Calendar) -> Date? {
        let step = TimeInterval(minutes * 60)
        var candidate: Date
        if let last = lastDone, last + step > after {
            candidate = last + step
        } else if let last = lastDone {
            // Overdue. If the drink happened during the current window period, fire now;
            // otherwise the day started fresh — count from this period's start.
            if w.contains(after, calendar: calendar), let start = periodStart(w, containing: after, calendar: calendar) {
                candidate = last >= start ? after : max(start + step, after)
            } else {
                candidate = after + step
            }
        } else {
            candidate = after + step
        }

        for _ in 0..<horizonDays {
            if w.contains(candidate, calendar: calendar) { return candidate }
            guard let next = nextWindowStart(w, onOrAfter: candidate, calendar: calendar) else { return nil }
            candidate = next + step
        }
        return nil
    }

    private static func clockAligned(_ w: ActiveWindow, minutes: Int, after: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: after)
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for k in stride(from: 0, to: 24 * 60, by: minutes) {
                let d = day + TimeInterval(k * 60)
                if d > after && w.contains(d, calendar: calendar) { return d }
            }
        }
        return nil
    }

    private static func atTimes(_ w: ActiveWindow, times: [ClockTime], after: Date, calendar: Calendar) -> Date? {
        guard !times.isEmpty else { return nil }
        let today = calendar.startOfDay(for: after)
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for t in times {
                let d = day + TimeInterval(t.minutesSinceMidnight * 60)
                if d > after && w.contains(d, calendar: calendar) { return d }
            }
        }
        return nil
    }

    static func periodStart(_ w: ActiveWindow, containing d: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: w.start.hour, minute: w.start.minute, second: 0, of: d)
    }

    static func nextWindowStart(_ w: ActiveWindow, onOrAfter d: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: d)
        for offset in 0...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let s = periodStart(w, containing: day, calendar: calendar) else { continue }
            if s >= d && w.weekdays.contains(calendar.component(.weekday, from: s)) { return s }
        }
        return nil
    }
}
