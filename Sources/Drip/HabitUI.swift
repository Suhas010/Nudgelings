import SwiftUI
import DripCore

extension HabitKind {
    /// Length of the timed gags (eyes countdown, guided stretch); nil for click-to-finish habits.
    var gagSeconds: TimeInterval? {
        switch self {
        case .eyes: 20
        case .stretch: 30
        default: nil
        }
    }

    static let wiperSeconds: TimeInterval = 1.2
}

let snoozeLabel = "Snooze \(Int(ReminderEngine.snoozeSeconds / 60))m 😅"

/// Encodes a SwiftUI view as PNG at 1× (the view's own point size is the pixel size).
@MainActor
func pngData(of view: some View) -> Data? {
    let r = ImageRenderer(content: view)
    r.scale = 1
    guard let cg = r.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}
