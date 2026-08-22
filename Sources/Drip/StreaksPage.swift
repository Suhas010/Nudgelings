import SwiftUI
import DripCore

/// Design 1l: the week at a glance, your streak, and the last few weeks.
struct StreaksPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Navigation

    var body: some View {
        let streak = model.streak
        let week = model.week
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week").font(.display(34, .bold)).foregroundStyle(Theme.text)
                    Text("A day counts when you hit half its goals. Days off don't break your streak.")
                        .font(.body(13.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Share my week") { go(.share(.week)) }.buttonStyle(ToyButton(fill: Theme.aqua, size: 13))
            }

            HStack(spacing: 14) {
                StatTile(big: "\(streak.current)", title: "day streak",
                         sub: streak.current > 0 && streak.current >= streak.best ? "Your best yet. \(HabitKind.walk.character) is doing a lap." : "Best: \(streak.best) days",
                         fill: Color(light: 0x6fcf6f, dark: 0x2f6b34), kind: .walk, wide: true)
                    .entrance(0)
                if model.settings.config(.water).enabled {
                    StatTile(big: "\(model.weekTotal(.water))", title: "glasses of water", sub: nil, fill: HabitKind.water.wash, kind: .water)
                        .entrance(1)
                }
                if model.settings.config(.eyes).enabled {
                    StatTile(big: "\(model.weekTotal(.eyes))", title: "eye breaks taken", sub: nil, fill: HabitKind.eyes.wash, kind: .eyes)
                        .entrance(2)
                }
            }

            WeekGrid(model: model, week: week).entrance(3)

            RecentDays(model: model).entrance(4)
        }
    }

    private func go(_ p: Navigation.Page) { withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { nav.page = p } }
}

private struct StatTile: View {
    let big: String
    let title: String
    let sub: String?
    let fill: Color
    let kind: HabitKind
    var wide = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(big).font(.display(wide ? 58 : 44, .bold)).monospacedDigit().contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.display(17, .semibold))
                if let sub { Text(sub).font(.body(12.5)).opacity(0.85).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            CharacterView(kind: kind, expression: .happy, size: 44, animated: true)
        }
        .foregroundStyle(Theme.text)
        .padding(16)
        .frame(maxWidth: wide ? .infinity : 220, minHeight: 96, alignment: .leading)
        .toyCard(fill, radius: 18, shadow: 4)
    }
}

/// Rows per character, a square per day: full = goal hit, tint = some done, grey = nothing.
private struct WeekGrid: View {
    @ObservedObject var model: AppModel
    let week: [(date: Date, stats: DayStats?)]
    private let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let kinds = model.settings.enabledKinds
        let today = AppModel.calendar.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("").frame(width: 90, alignment: .leading)
                ForEach(0..<7, id: \.self) { i in
                    Text(letters[i]).font(.display(12.5, .semibold))
                        .foregroundStyle(week[i].date == today ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(kinds) { k in
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        CharacterView(kind: k, expression: .happy, size: 20, shadow: false)
                        Text(k.character).font(.display(13, .semibold)).foregroundStyle(Theme.text)
                    }
                    .frame(width: 90, alignment: .leading)
                    ForEach(0..<7, id: \.self) { i in
                        cell(k, week[i], future: week[i].date > today)
                    }
                }
            }
            if kinds.isEmpty {
                Text("Hire some of the crew to start a streak.").font(.body(13)).foregroundStyle(Theme.muted)
            }
            Text("A full square means that day's goal was hit.").font(.body(12)).foregroundStyle(Theme.muted).padding(.top, 4)
        }
        .padding(18)
        .toyCard(Theme.raised, radius: 18, shadow: 4)
    }

    @ViewBuilder
    private func cell(_ k: HabitKind, _ day: (date: Date, stats: DayStats?), future: Bool) -> some View {
        let done = day.stats?.done[k] ?? 0
        let goal = day.stats?.goals[k] ?? model.settings.config(k).goal
        let full = done >= goal && goal > 0
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(future ? Color.clear : full ? k.color : done > 0 ? k.color.opacity(0.35) : Theme.text.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(future ? Theme.muted.opacity(0.3) : full ? Theme.outline : .clear,
                              style: StrokeStyle(lineWidth: full ? 2 : 1.5, dash: future ? [4, 3] : [])))
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .help(future ? "" : "\(done) of \(goal)")
    }
}

/// The last three weeks as little bars, green when the day counted.
private struct RecentDays: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let days = Array((model.state.history + [model.state.stats]).suffix(21))
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST 3 WEEKS").font(.display(12.5, .semibold)).foregroundStyle(Theme.muted)
            if days.count <= 1 {
                Text("Your history starts today. Come back tomorrow for bars. 📊").font(.body(13)).foregroundStyle(Theme.muted)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        let f = d.fraction
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(f >= Streak.goodDay ? Theme.leaf : Theme.text.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.outline.opacity(f >= Streak.goodDay ? 1 : 0), lineWidth: 1.5))
                                .frame(height: max(6, 80 * f))
                            Text(String(d.day.suffix(2))).font(.body(10, .bold)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(d.day): \(Int(f * 100))%")
                    }
                }
                .frame(height: 100, alignment: .bottom)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toyCard(Theme.raised, radius: 18, shadow: 4)
    }
}
