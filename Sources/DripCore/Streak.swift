import Foundation

/// Consecutive good days. A day is good when at least half of its goals were hit.
/// Days nobody is on shift (e.g. weekends) are skipped: they neither count nor break the streak,
/// and today only counts once it's good (an unfinished today never breaks it).
public enum Streak {
    public static let goodDay = 0.5

    public static func compute(history: [DayStats], today: DayStats, settings: Settings, calendar: Calendar)
        -> (current: Int, best: Int) {
        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let fmt = DateFormatter()
        fmt.calendar = calendar; fmt.timeZone = calendar.timeZone; fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let todayDate = fmt.date(from: today.day) else { return (0, 0) }
        let workdays = Set(settings.enabledKinds.flatMap { settings.config($0).window.weekdays })

        func stats(_ key: String) -> DayStats? { key == today.day ? today : byDay[key] }
        func isWorkday(_ d: Date) -> Bool { workdays.contains(calendar.component(.weekday, from: d)) }

        // Walk from the oldest recorded day to today.
        let oldest = history.compactMap { fmt.date(from: $0.day) }.min() ?? todayDate
        var d = oldest, run = 0, best = 0
        while d <= todayDate {
            let key = fmt.string(from: d)
            if isWorkday(d) || stats(key)?.fraction ?? 0 > 0 {
                let good = (stats(key)?.fraction ?? 0) >= goodDay
                if good { run += 1 } else if key != today.day { run = 0 }
                best = max(best, run)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return (run, best)
    }
}
