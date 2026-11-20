import AppKit
import SwiftUI

/// Lets things outside the window (links, Shortcuts actions) bring a screen forward.
@MainActor
final class Navigator: ObservableObject {
    static let shared = Navigator()

    /// The window shows this screen as soon as it sees a value, then clears it.
    @Published var request: AppSection?

    /// Bring the app forward, optionally on a specific screen. Reopens the window if it was closed.
    func reveal(_ section: AppSection?) {
        if let section { request = section }
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSWorkspace.shared.open(Bundle.main.bundleURL)      // triggers the app's "reopen", which makes a window
        }
    }
}
