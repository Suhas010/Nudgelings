import AppKit

MainActor.assumeIsolated {
    if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
        Snapshots.icon(to: CommandLine.arguments[i + 1])
        exit(0)
    }
    if CommandLine.arguments.contains("--snapshot") {
        // Dev aid: render key views to PNGs so visuals can be checked without clicking around.
        Snapshots.run()
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
