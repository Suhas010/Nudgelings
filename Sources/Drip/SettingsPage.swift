import SwiftUI
import ServiceManagement
import DripCore

/// Settings as a set of little toy cards, each looked after by a crew member.
struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @State private var loginError: String?
    @State private var loginOn = SMAppService.mainApp.status == .enabled

    private func binding(_ key: WritableKeyPath<DripCore.Settings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] },
                set: { v in withAnimation(.spring(response: 0.4)) { var s = model.settings; s[keyPath: key] = v; model.update(s) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(.display(34, .bold)).foregroundStyle(Theme.text)
                    Text("The crew's house rules. Nothing here leaves your Mac.").font(.body(14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                CrewRow(size: 38)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)], spacing: 16) {
                SettingCard(kind: .water, title: "Hydration line",
                            text: "A thin water level along the bottom of your screen that drains as you get thirsty.",
                            isOn: binding(\.bottomWaterLine)) {
                    WaterLinePreview(level: model.state.hydration.level, on: model.settings.bottomWaterLine)
                }
                .entrance(0)

                SettingCard(kind: .eyes, title: "Hush during calls",
                            text: "Stays quiet while your camera or mic is on, or an app is full screen. It only checks whether they're in use.",
                            isOn: binding(\.autoHush)) {
                    HushPreview(on: model.settings.autoHush)
                }
                .entrance(1)

                SettingCard(kind: .breathe, title: "Sound volume",
                            text: "How loud the brook, rain, chimes and birds are when a sound cue plays.", isOn: nil) {
                    VolumeControl(model: model)
                }
                .entrance(2)

                SettingCard(kind: .stand, title: "Open at login",
                            text: "The crew clocks in with you, so nobody misses the first sip of the day.",
                            isOn: Binding(get: { loginOn }, set: { on in
                                do {
                                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                    loginOn = on; loginError = nil
                                } catch { loginError = "Couldn't change this: \(error.localizedDescription)" }
                            })) {
                    if let loginError {
                        Text(loginError).font(.body(12)).foregroundStyle(HabitKind.stretch.accent)
                    }
                }
                .entrance(3)

                SettingCard(kind: .walk, title: "Take the tour again",
                            text: "Meet the crew, pick your team and set your desk hours from the start.", isOn: nil) {
                    Button("Replay welcome") { model.replayOnboarding?() }
                        .buttonStyle(ToyButton(fill: Theme.leaf, size: 13))
                }
                .entrance(4)

                SettingCard(kind: .posture, title: "Your data",
                            text: "Settings and history are plain files on this Mac. No accounts, no tracking, no network.", isOn: nil) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.defaultDirectory]) }
                        .buttonStyle(ToyButton(fill: .white, size: 13))
                }
                .entrance(5)
            }
        }
    }
}

/// A settings card: mascot, title, explanation, an optional switch, and a little live preview.
private struct SettingCard<Extra: View>: View {
    let kind: HabitKind
    let title: String
    let text: String
    var isOn: Binding<Bool>?
    @ViewBuilder var extra: Extra
    @State private var bump = 0
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CharacterView(kind: kind, expression: (isOn?.wrappedValue ?? true) ? .happy : .sleepy, size: 46, animated: true, bump: bump)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.display(17, .semibold)).foregroundStyle(Theme.text)
                    Text(text).font(.body(12.5)).foregroundStyle(Theme.text.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if let isOn {
                    Toggle("", isOn: Binding(get: { isOn.wrappedValue }, set: { v in isOn.wrappedValue = v; if v { bump += 1 } }))
                        .toggleStyle(ToySwitch())
                }
            }
            extra
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
        .toyCard(kind.wash, radius: 18, shadow: hovering ? 6 : 4)
        .offset(y: hovering ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Tiny screen with the hydration line along its bottom edge.
private struct WaterLinePreview: View {
    let level: Double
    let on: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xfbfdfb))
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Theme.ink.opacity(0.1)).frame(width: CGFloat(120 - i * 26), height: 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10).frame(maxHeight: .infinity, alignment: .top)
            if on {
                GeometryReader { g in
                    Capsule().fill(LinearGradient(colors: [waterLight, waterDeep], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * max(0.04, level), height: 5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .animation(.spring(response: 0.6), value: level)
                }
                .padding(.horizontal, 3).padding(.bottom, 3)
                .transition(.opacity)
            }
        }
        .frame(height: 62)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ink.opacity(0.6), lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            Text(on ? "\(Int(level * 100))% hydrated" : "off").font(.body(10.5, .bold)).foregroundStyle(Theme.ink.opacity(0.6)).padding(8)
        }
    }
}

private struct HushPreview: View {
    let on: Bool
    var body: some View {
        HStack(spacing: 8) {
            ForEach([("video.fill", "Camera"), ("mic.fill", "Mic"), ("arrow.up.left.and.arrow.down.right", "Full screen")], id: \.1) { icon, label in
                HStack(spacing: 5) {
                    Image(systemName: on ? icon : icon).font(.system(size: 11, weight: .bold))
                    Text(label).font(.body(11.5, .bold))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? Theme.ink : Theme.muted)
                .background(Capsule().fill(on ? Color.white : Color.clear))
                .overlay(Capsule().strokeBorder(on ? Theme.ink : Theme.muted.opacity(0.4), lineWidth: 1.5))
            }
            if on { Text("🤫").font(.system(size: 16)) }
        }
        .animation(.spring(response: 0.35), value: on)
    }
}

private struct VolumeControl: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(Theme.text.opacity(0.6))
            Slider(value: Binding(get: { model.settings.soundVolume },
                                  set: { v in var s = model.settings; s.soundVolume = v; model.update(s) }), in: 0...1)
                .tint(Theme.lilac)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.text.opacity(0.6))
            Button("Test") { model.sound.play(.brook, seconds: 4) }.buttonStyle(ToyButton(fill: Theme.lilac, size: 12.5))
        }
    }
}
