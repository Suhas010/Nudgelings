import Foundation

public enum Mood: String, Codable, Sendable, CaseIterable {
    case hydrated, thirsty, parched
}

/// Drip's water level. Drains linearly to 0 over 2× the water interval; each drink adds 35%.
public struct HydrationState: Codable, Equatable, Sendable {
    public static let perDrink = 0.35

    public var level: Double
    public var updatedAt: Date

    public init(level: Double, updatedAt: Date) {
        self.level = min(1, max(0, level)); self.updatedAt = updatedAt
    }

    public static func full(at date: Date) -> HydrationState { HydrationState(level: 1, updatedAt: date) }

    public func drained(to now: Date, waterIntervalMinutes: Int) -> HydrationState {
        let elapsed = now.timeIntervalSince(updatedAt)
        guard elapsed > 0, waterIntervalMinutes > 0 else { return self }
        let rate = 1 / (2 * Double(waterIntervalMinutes) * 60)
        return HydrationState(level: level - elapsed * rate, updatedAt: now)
    }

    public func drinking(at now: Date) -> HydrationState {
        HydrationState(level: level + Self.perDrink, updatedAt: now)
    }

    public var mood: Mood {
        switch level {
        case 0.66...: .hydrated
        case 0.33...: .thirsty
        default: .parched
        }
    }
}
