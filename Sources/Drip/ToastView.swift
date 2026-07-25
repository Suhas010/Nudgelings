import SwiftUI
import DripCore

extension HabitKind {
    /// Corner-toast headline, in the character's voice (design 1h).
    var toastTitle: String {
        switch self {
        case .water: "Drip misses you."
        case .eyes: "Peep says blink."
        case .walk: "Walkies?"
        case .stretch: "Noodle wants a stretch."
        case .posture: "Sprout sat up straight."
        case .breathe: "Breathe with Puff"
        case .stand: "Pop! Up you get."
        }
    }

    var actionLabel: String {
        switch self {
        case .water: "Sipped"
        case .eyes: "Start"
        case .walk: "Going"
        case .stretch: "Stretch"
        case .posture: "Did it"
        case .breathe: "Go"
        case .stand: "Standing"
        }
    }
}

/// The top-right card: character, what they want, one big yes and a "later".
///
/// Motion: drops in from under the menu bar with an overshoot, the character peeks up into it,
/// a small attention wiggle every few seconds, and a flick up-and-away on the way out.
struct ToastView: View {
    @ObservedObject var model: AppModel
    /// What's on the card; kept briefly after dismissal so the exit can play.
    @State private var shown: Presentation?
    @State private var visible = false
    @ObservedObject private var motion = Motion.shared

    var body: some View {
        ZStack(alignment: .top) {
            if let p = shown { card(p) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { sync(model.presentation) }
        .onChange(of: model.presentation) { _, p in sync(p) }
    }

    private func sync(_ p: Presentation?) {
        if let p, p.wantsToast {
            let fresh = shown?.attemptStartedAt != p.attemptStartedAt || shown?.kind != p.kind
            shown = p
            if fresh && !Motion.snapshot {
                visible = false
                DispatchQueue.main.async { withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { visible = true } }
            } else { visible = true }
        } else if shown != nil {
            withAnimation(.easeIn(duration: 0.22)) { visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if model.presentation?.wantsToast != true { shown = nil } }
        }
    }

    private func card(_ p: Presentation) -> some View {
        let kind = p.kind
        let dark = kind == .breathe || kind == .stand
        let still = motion.reduced
        return TimelineView(.periodic(from: .now, by: 5.5)) { tl in
            HStack(spacing: 12) {
                CharacterView(kind: kind, expression: kind == .water ? model.mood.expression : .happy, size: 46, animated: true,
                              bump: Int(tl.date.timeIntervalSinceReferenceDate / 5.5))
                    .offset(y: visible || still ? 0 : 34)
                    .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.12), value: visible)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.toastTitle).font(.display(15.5, .semibold))
                    Text(subtitle(kind)).font(.body(12.5, .semibold)).opacity(0.75).lineLimit(2)
                }
                .foregroundStyle(dark ? Color.white : Theme.ink)
                Spacer(minLength: 4)
                VStack(spacing: 6) { primary(kind, p); later }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: 400)
            .toyCard(dark ? Color(hex: 0x1d2e27) : Color(hex: 0xfbfdfb), radius: 18)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous).inset(by: -8))
            .keyframeAnimator(initialValue: 0.0, trigger: still ? 0 : Int(tl.date.timeIntervalSinceReferenceDate / 5.5)) { v, angle in
                v.rotationEffect(.degrees(angle), anchor: .top)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(2.6, duration: 0.09)
                    CubicKeyframe(-2.2, duration: 0.12)
                    CubicKeyframe(1.4, duration: 0.12)
                    CubicKeyframe(-0.6, duration: 0.1)
                    SpringKeyframe(0, duration: 0.3)
                }
            }
        }
        .padding(10)
        .offset(y: visible || still ? 0 : -150)
        .rotationEffect(.degrees(visible || still ? 0 : -6), anchor: .topTrailing)
        .scaleEffect(visible ? 1 : 0.92, anchor: .top)
        .opacity(visible ? 1 : 0)
    }

    private func subtitle(_ kind: HabitKind) -> String {
        let c = model.settings.config(kind)
        let done = model.state.stats.done[kind] ?? 0
        switch kind {
        case .water: return "One sip? You're at \(done) of \(c.goal)."
        case .eyes: return "20 seconds, far away. Go."
        case .walk: return "A 5-min loop to the kitchen and back."
        case .stretch: return "30 seconds. Arms up, lean left, lean right."
        case .posture: return "Just saying. No reason."
        case .breathe: return "In for 4… out for 6. Three times."
        case .stand: return "You've been sitting a while."
        }
    }

    @ViewBuilder
    private func primary(_ kind: HabitKind, _ p: Presentation) -> some View {
        let timed = p.has(.gag) && kind.gagSeconds != nil
        if timed, let start = model.gagStartedAt, let total = kind.gagSeconds {
            TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                let left = max(0, total - tl.date.timeIntervalSince(start))
                Text("\(Int(left.rounded(.up)))s").font(.display(18, .bold)).monospacedDigit()
                    .frame(width: 78, height: 30)
                    .toyCard(kind.color, radius: 10, shadow: 3)
            }
        } else if timed {
            Button(kind.actionLabel) { model.startGagTimer() }.buttonStyle(ToyButton(fill: kind.color, size: 12.5))
        } else {
            // "Start" only makes sense for the timed gag; otherwise the button just says it's done.
            Button(kind == .eyes ? "Looked away" : kind.actionLabel) { model.done() }
                .buttonStyle(ToyButton(fill: kind.color, size: 12.5))
        }
    }

    private var later: some View {
        Button("Later") { model.snooze() }.buttonStyle(ToyButton(fill: .white, size: 12.5)).help("Esc works too")
    }
}
