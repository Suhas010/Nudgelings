<img width="1496" height="843" alt="Screenshot 2026-09-30 at 2 42 49 PM" src="https://github.com/user-attachments/assets/9f403385-0440-43d4-8533-9daf4737aacd" />

# Nudgelings

A tiny crew that lives in your menu bar and gently bullies you into being healthy. Seven characters each look after one habit:

| | Character | Habit |
|---|---|---|
| 💧 | **Drip** | Drink water |
| 👁 | **Peep** | Rest your eyes (20-20-20) |
| 🟩 | **Stompy** | Take a walk |
| 🔴 | **Noodle** | Stretch |
| 🌱 | **Sprout** | Fix your posture |
| 🟣 | **Puff** | Breathe |
| 🟧 | **Pop** | Stand up |

## Install

1. Open `Nudgelings-<version>.dmg` and drag **Nudgelings** onto **Applications**.
2. Open it from Applications.
   - If you open it straight from the disk image, Nudgelings offers to move itself to Applications first. That way "Open at login" keeps working after you eject the disk image.
3. The welcome tour takes about 40 seconds:
   - who's on your team
   - how loud the first nudge should be
   - how pushy it gets if you ignore it
   - your desk hours
4. There's no Dock icon. The crew lives in your **menu bar** (top right). Click Drip for today's progress, pausing, and the main window.

**First launch on another Mac.** Builds without an Apple Developer ID aren't notarised, so macOS blocks the first launch.
- On macOS 15 and later: open **System Settings › Privacy & Security** and click **Open Anyway** next to Nudgelings.
- On macOS 14: right-click the app and choose **Open**.

You only need to do this once.

## How it works

- **Pick how loud.** Each character uses one of four levels. The editor reads your setup back as one plain sentence, e.g. "Drip will slide a card into the corner every 45 min…".
  - **Subtle:** only the menu-bar icon wiggles.
  - **Polite:** a small card in the corner with Done and Later.
  - **Playful:** the character strolls across your screen, leaves a cursor trail or pulls a screen prank. Clicks go right through.
  - **Unmissable:** dims the screen, or a full-screen break or mini-game.

  Every style has a ▶ preview, and a sound can ride along with any level.
- **Ignore it, and it comes back louder.** Each retry steps up a level. The editor draws the exact ladder for each character. **Pushiness** (Gentle, Nag or Max) sets how far it goes; Gentle never blocks your screen.
- **Your schedule, per character:**
  - every N minutes, counted from the last time you did it or aligned to the clock;
  - or at set times;
  - each with its own days and hours.
- **Auto-hush.** Reminders wait while your camera or mic is on, a full-screen app is in front, or your Mac is locked or asleep.
- **Streaks and sharing.** Daily streaks, a weekly history, and share cards you can post.
- **Private.** No network access, no accounts, no telemetry. Settings and history are JSON files in `~/Library/Application Support/Nudgelings/`. Auto-hush only checks whether the camera or mic is in use; it never records anything.

## Build

Requires macOS 14+ and the Xcode Command Line Tools (full Xcode not needed).

```bash
scripts/build-app.sh      # → dist/Nudgelings.app (release, ad-hoc signed)
scripts/make-dmg.sh       # → dist/Nudgelings-<version>.dmg (drag-to-Applications window)
```

`make-dmg.sh` builds a universal app (Apple Silicon and Intel) and renders the installer background with the app itself. Then it lays out the Finder window and compresses the image.
- The first run asks to let your terminal control Finder. Allow it to get the styled window. If you decline, you get a plain but working DMG.
- The version comes from `Resources/Info.plist`.

**Sharing it yourself (free).** Next to the DMG, `make-dmg.sh` writes `Nudgelings-<version>.dmg.sha256` and `dist/download-snippet.html`. That's a styled download block with install steps and the checksum, ready to paste into a website. Upload the DMG next to the page, or attach it to a GitHub release and point the link there. Visitors approve the app once in System Settings; the DMG window and the snippet both explain how.

**Shipping without the Gatekeeper prompt.** You need an Apple Developer ID. Set these two variables, and the script signs with the hardened runtime, notarises, and staples:

```bash
xcrun notarytool store-credentials nudgelings-notary   # once: Apple ID, team ID, app-specific password
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=nudgelings-notary scripts/make-dmg.sh
```

## Develop

```bash
scripts/test.sh                                   # DripCore unit tests (Swift Testing)
swift build && .build/debug/Drip                  # run unbundled (notifications need the .app)
.build/debug/Drip --snapshot out/                 # render screens, onboarding, nudges, share cards to PNG
.build/debug/Drip --try water toast,sound         # preview a nudge on launch
```

| Module | What's in it |
|---|---|
| `Sources/DripCore` | Pure logic with an injected clock: models (habits, nudge levels), `Scheduler`, `Escalation`, `ReminderEngine`, `Store`, `Streak`, `Lines`. Unit-tested. |
| `Sources/Drip` | The AppKit/SwiftUI shell: menu bar, popover, main window, onboarding, overlay nudges, takeovers, sounds, hush detection, notifications, share studio, install-location check. |

## License

MIT, see [LICENSE](LICENSE). The bundled Fredoka and Nunito fonts are under the SIL Open Font License (`Resources/Fonts/OFL-*.txt`).
