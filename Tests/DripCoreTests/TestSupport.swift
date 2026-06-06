import Foundation
@testable import DripCore

/// Fixed calendar so tests never depend on the machine's locale or time zone.
let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

/// 2026-09-28 is a Monday.
func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 9) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

func t(_ h: Int, _ m: Int = 0) -> ClockTime { ClockTime(hour: h, minute: m) }
