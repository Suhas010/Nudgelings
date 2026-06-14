import Foundation

/// Local JSON persistence in Application Support. Corrupt or missing files fall back to defaults.
public struct Store: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nudgelings", isDirectory: true)
    }

    /// Where earlier builds kept their data, newest first ("Sip Happens", then "Drip").
    public static var legacyDirectories: [URL] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ["Sip Happens", "Drip"].map { base.appendingPathComponent($0, isDirectory: true) }
    }

    /// Copies an old data folder into place once. Never touches an existing destination.
    public static func migrate(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) else { return }
        try? fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: old, to: new)
    }

    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    public func loadSettings() -> Settings { load(Settings.self, from: settingsURL) ?? .initial }
    public func loadState() -> EngineState? { load(EngineState.self, from: stateURL) }

    public func save(_ settings: Settings) throws { try write(settings, to: settingsURL) }
    public func save(_ state: EngineState) throws { try write(state, to: stateURL) }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(value).write(to: url, options: .atomic)
    }
}
