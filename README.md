<img width="1811" height="1016" alt="Screenshot 2026-09-30 at 2 38 03 PM" src="https://github.com/user-attachments/assets/43ca1ff6-8c1b-4ff7-8c3c-9c3716710fc1" />

# Nudgelings

A macOS menu-bar app that nags you to drink water, rest your eyes, fix your posture, stretch and walk. Instead of sending banners you dismiss on reflex, it makes the screen react:


- **Water:** waves roll across your menu bar. Ignore them and bubbles rise, then water fills your screen, and then a fish swims past your Slack.
- **Eyes (20-20-20):** your screen fogs up, and a wiper clears it after 20 seconds of looking away.
- **Posture:** the screen tilts until you sit up straight.
- **Stretch:** the screen wobbles like jelly, and Drip walks you through 30 seconds of stretches.
- **Walk:** footprints walk off your screen.

The mascot is **Drip**, a melodramatic droplet who lives in your menu bar. Drip is plump when you're hydrated and a wrinkly raisin when you're not ("tell my mom I loved her").

## Features

- **Every habit is opt-in.** Pick your habits on first launch and change them any time in Settings.
- **Your schedule, per habit.**
  - **Every N minutes or hours**, counted from the last time you did it or aligned to the clock (:00, :30, and so on).
  - **At set times**, for example 10:00, 12:30 and 15:00.
  - Each habit has its own active days and hours (default weekdays 9–6).
- **A macOS notification per habit:** a banner with Done and Snooze, on top of whatever screen effect you pick. It's on by default and you can turn it off per habit.
- **Your chaos level, per habit:**
  - 🤫 **Whisper:** only Drip hops in the menu bar.
  - 🔔 **Notification:** a normal banner, in Drip's voice.
  - 🌊 **Menu-bar waves**
  - 🎭 **Signature gag:** fog, tilt, jelly or footprints, depending on the habit.
  - 🐟 **Flood** (water only): escalates every 5 minutes.
  - Optionally, **escalate if ignored**.
- **Auto-hush.** If your camera or mic is in use, or a full-screen app is in front, reminders wait. They come back 2 minutes after the meeting ends ("You survived the meeting. Now DRINK."). Locking the screen or sleeping counts too.
- **Hydration Wrapped.** Choose *Share today* to export a 1080×1350 card of your day to `~/Downloads`.
- **Private.** No network access, no accounts, no telemetry. Everything is stored as JSON in `~/Library/Application Support/Nudgelings/`. Auto-hush only reads whether the camera or mic is on; it never records anything.

## Build & run

Requires macOS 14+ and the Xcode Command Line Tools (full Xcode not needed).

```bash
scripts/build-app.sh          # → "dist/Nudgelings.app" (release, ad-hoc signed)
open "dist/Nudgelings.app"
```

Nudgelings is not notarised, so the first time you open a copy on another Mac, right-click it and choose **Open**.

## Develop

```bash
scripts/test.sh                          # unit tests for DripCore (Swift Testing)
swift build && .build/debug/Drip         # run unbundled (notifications need the .app)
.build/debug/Drip --snapshot out/        # render faces, gags and share card to PNG
"dist/Nudgelings.app/Contents/MacOS/Drip" --try water flood   # fire a fast preview on launch
```

| Module | What's in it |
|---|---|
| `Sources/DripCore` | Pure logic with an injected clock: models, `Scheduler`, `Escalation`, `HydrationState`, `ReminderEngine`, `Store`, `Lines`. Fully unit-tested. |
| `Sources/Drip` | The AppKit/SwiftUI shell: menu-bar glass, click-through overlay panels, water and gag rendering, the pill, settings, onboarding, hush detection, notifications, share card. |

## License

MIT, see [LICENSE](LICENSE). The bundled Fredoka and Nunito fonts are under the SIL Open Font License (`Resources/Fonts/OFL-*.txt`).
