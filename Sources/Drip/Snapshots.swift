import AppKit
import SwiftUI
import DripCore

/// `Drip --snapshot <dir>` renders key screens to PNG for quick visual review.
@MainActor
enum Snapshots {
    static func run() {
        Fonts.register()
        Motion.snapshot = true
        let args = CommandLine.arguments
        let dir = URL(fileURLWithPath: args.last.flatMap { $0 == "--snapshot" ? nil : $0 } ?? "snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()

        // A model with some of the day done, backed by a throwaway store.
        let model = AppModel(store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("nudge-snap-\(UUID())")))
        var s = model.settings
        for k in [HabitKind.water, .eyes, .walk, .stretch, .posture] { s.habits[k]!.enabled = true }
        s.habits[.walk]!.schedule = .atTimes([ClockTime(hour: 11, minute: 30), ClockTime(hour: 15, minute: 0)])
        s.onboarded = true
        model.update(s)
        for _ in 0..<4 { model.logDone(.water) }
        model.logDone(.eyes); model.logDone(.eyes); model.logDone(.walk)

        // Crew lineup, all expressions
        let crew = VStack(spacing: 20) {
            HStack(alignment: .bottom, spacing: 22) { ForEach(HabitKind.allCases) { CharacterView(kind: $0, expression: .happy, size: 120) } }
            HStack(alignment: .bottom, spacing: 22) {
                ForEach([Expression.calm, .happy, .cheer, .worried, .sad, .sleepy], id: \.self) { CharacterView(kind: .water, expression: $0, size: 90) }
                ForEach([Expression.calm, .worried, .sleepy], id: \.self) { CharacterView(kind: .eyes, expression: $0, size: 90) }
            }
        }
        .padding(30).background(Color(hex: 0xeef1ef))
        save(crew, "crew", dir)

        // Pose filmstrip: what the idle choreography moves
        func posed(_ k: HabitKind, _ e: Expression = .happy, _ f: (inout Pose) -> Void) -> some View {
            var p = Pose()
            f(&p)
            return Canvas { ctx, sz in CharacterPainter(kind: k, expression: e, pose: p).draw(&ctx, sz) }.frame(width: 96, height: 96)
        }
        let film = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                posed(.water) { $0.look = CGVector(dx: -1, dy: 0) }
                posed(.water) { $0.look = CGVector(dx: 1, dy: -0.8) }
                posed(.water) { $0.blink = 0.6 }
                posed(.water, .cheer) { _ in }
                posed(.eyes) { $0.look = CGVector(dx: -0.9, dy: 0.5) }
                posed(.eyes) { $0.pupil = 1.45 }
                posed(.eyes) { $0.blink = 0.55 }
            }
            HStack(spacing: 14) {
                posed(.walk) { $0.legLift = (1, 0) }
                posed(.stretch) { $0.ear = 0.45 }
                posed(.stretch) { $0.ear = -0.45 }
                posed(.posture) { $0.leaf = 0.5 }
                posed(.breathe, .cheer) { _ in }
                posed(.stand) { $0.look = CGVector(dx: 1, dy: 1) }
                posed(.stand, .cheer) { _ in }
            }
        }
        .padding(20).background(Color(hex: 0xeef1ef))
        save(film, "poses", dir)
        save(RevealMask(progress: 0.45, origin: CGPoint(x: 1290, y: -10)).frame(width: 1440, height: 900)
                .background(Color.white).compositingGroup(), "reveal-mask", dir)

        // Popover, main window pages, onboarding
        save(MenuPopover(model: model, openMain: { _ in }, share: {}).environment(\.colorScheme, .light), "popover", dir)
        save(page(CrewPage(model: model, nav: .shared)), "main-crew", dir)
        save(page(HabitEditor(model: model, notifier: model.notifier, kind: .water)), "main-editor-water", dir)
        save(page(StylesPage(model: model)), "main-styles", dir)
        save(page(AboutPage()), "main-about", dir)
        save(PushinessPicker(selection: .constant(.nag)).padding(20).frame(width: 520).background(Theme.paper), "pushiness", dir)
        save(TimeGrid(time: .constant(ClockTime(hour: 9, minute: 30)), tint: HabitKind.eyes.color) {}, "time-grid", dir)
        save(HoursRow(window: .constant(.workdays), tint: HabitKind.eyes.color).padding(16).background(Theme.raised), "hours-row", dir)
        save(page(VStack(alignment: .leading, spacing: 12) { StartNextButton(model: model, wide: false); PauseMenu(model: model) }), "controls", dir)
        Navigation.shared.page = .editor(.eyes)
        save(Sidebar(model: model, nav: .shared).frame(height: 560).background(Theme.canvas), "light-sidebar", dir)
        save(MenuPopover(model: model, openMain: { _ in }, share: {}, maxHeight: 560).environment(\.colorScheme, .light),
             "popover-short-screen", dir)

        // Nudges on a fake desktop
        let size = CGSize(width: 1440, height: 900)
        func scene(_ kind: HabitKind, _ types: [NudgeType], ago: Double = 30, water: Double = 0) -> OverlayScene {
            var sc = OverlayScene()
            sc.presentation = Presentation(kind: kind, types: types, attempt: 0, showing: true,
                                           attemptStartedAt: now.addingTimeInterval(-ago), isPreview: true)
            sc.water = Tween(from: water, to: water, start: .distantPast)
            sc.line = Lines.all(.reminder(kind))[0]
            sc.mood = .thirsty
            return sc
        }
        let shots: [(String, OverlayScene)] = [
            ("nudge-walk-across", scene(.walk, [.walkAcross], ago: 8)),
            ("nudge-dim-eyes", scene(.eyes, [.dim], ago: 6)),
            ("nudge-dim-posture", scene(.posture, [.dim])),
            ("nudge-gag-water", scene(.water, [.gag], ago: 60, water: 0.35)),
            ("nudge-gag-breathe", scene(.breathe, [.gag], ago: 2)),
            ("nudge-gag-stand", scene(.stand, [.gag], ago: 0.6)),
        ]
        for (name, sc) in shots {
            save(ZStack { FakeDesktop(); SceneCanvas(scene: sc, menuBarHeight: 32, fixedDate: now) }
                    .frame(width: size.width, height: size.height), name, dir)
        }
        for kind in HabitKind.allCases {
            let strip = ZStack { FakeDesktop(); SceneCanvas(scene: scene(kind, [.menuShow]), menuBarHeight: 32, fixedDate: now) }
                .frame(width: size.width, height: size.height)
                .frame(width: size.width, height: 110, alignment: .top).clipped()
            save(strip, "strip-\(kind.rawValue)", dir)
        }

        // Toast family + takeovers (these read the live model)
        for kind in [HabitKind.water, .eyes, .breathe, .stand] {
            model.previewNudges(kind, types: [.toast])
            save(ToastView(model: model).frame(width: 440, height: 110), "toast-\(kind.rawValue)", dir)
        }
        let takeovers: [(HabitKind, NudgeType)] = [(.water, .takeover), (.eyes, .takeover), (.stretch, .miniGame),
                                                    (.water, .miniGame), (.walk, .takeover)]
        for (kind, t) in takeovers {
            model.previewNudges(kind, types: [t])
            save(TakeoverView(model: model).frame(width: size.width, height: size.height), "takeover-\(kind.rawValue)-\(t.rawValue)", dir)
        }
        model.sound.stop()

        for k in ShareKind.allCases {
            save(ShareCard(kind: k, facts: ShareFacts(model: model, name: ShareFacts.defaultName)), "share-\(k.rawValue)", dir)
        }
        save(page(StreaksPage(model: model, nav: .shared)), "main-streaks", dir)
        save(page(SettingsPage(model: model)), "main-settings", dir)

        let icons = HStack(spacing: 12) {
            ForEach(HabitKind.allCases) { k in
                Image(nsImage: FaceIcon.image(.init(kind: k, expression: .happy, frame: 0, badge: k == .eyes, sleepy: false)))
                    .resizable().frame(width: 44, height: 44)
            }
        }
        .padding(16).background(Color(white: 0.92))
        save(icons, "menubar-icons", dir)
        // Paused state + confirmation
        model.pause(hours: 1)
        save(MenuPopover(model: model, openMain: { _ in }, share: {}).environment(\.colorScheme, .light), "popover-paused", dir)
        save(page(CrewPage(model: model, nav: .shared)), "main-crew-paused", dir)
        model.resume()
        print("snapshots → \(dir.path)")
    }

    private static func page(_ v: some View) -> some View {
        v.padding(28).frame(width: 860, alignment: .topLeading).background(Theme.paper).environment(\.colorScheme, .light)
    }

    /// `Drip --icon <file.png>` renders the 1024px app icon.
    static func icon(to path: String) {
        Fonts.register()
        let v = ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous).fill(Theme.ink).frame(width: 824, height: 824).offset(y: 18)
            RoundedRectangle(cornerRadius: 230, style: .continuous).fill(Color(hex: 0xeafaff)).frame(width: 824, height: 824)
            Canvas { ctx, size in
                WaterPaint.body(&ctx, width: size.width, surface: size.height * 0.66, bottom: size.height, t: 1.3, amplitude: 18, bubbles: 8)
            }
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 230, style: .continuous))
            RoundedRectangle(cornerRadius: 230, style: .continuous).strokeBorder(Theme.ink, lineWidth: 26).frame(width: 824, height: 824)
            HStack(alignment: .bottom, spacing: -40) {
                CharacterView(kind: .eyes, expression: .happy, size: 300)
                CharacterView(kind: .water, expression: .happy, size: 470)
                CharacterView(kind: .walk, expression: .happy, size: 300)
            }
            .offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
        try? pngData(of: v)?.write(to: URL(fileURLWithPath: path))
    }

    private static func save<V: View>(_ view: V, _ name: String, _ dir: URL) {
        try? pngData(of: view)?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}

/// Stand-in desktop: wallpaper, a menu bar, and a window.
private struct FakeDesktop: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.8, green: 0.9, blue: 0.88), Color(red: 0.62, green: 0.78, blue: 0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.white.opacity(0.75)).frame(height: 32)
            HStack(spacing: 20) {
                Text("").font(.system(size: 16)); Text("Notion").bold(); Text("File"); Text("Edit"); Text("View"); Spacer()
                Text("Tue 11:02")
            }
            .font(.system(size: 14)).padding(.horizontal, 16).frame(height: 32)
            RoundedRectangle(cornerRadius: 12).fill(.white).frame(width: 760, height: 520).shadow(radius: 20)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Q3 planning").font(.title2.bold())
                        ForEach(0..<8, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25)).frame(width: CGFloat(300 + (i * 53) % 350), height: 12)
                        }
                    }.padding(24)
                }
                .offset(x: 120, y: 110)
        }
    }
}
