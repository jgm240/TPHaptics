import SwiftUI

/// Lets things outside the UI (Shortcuts actions, links) ask the app to show a screen.
@MainActor
final class Navigator: ObservableObject {
    static let shared = Navigator()
    /// RootView shows this screen as soon as it sees a value, then clears it.
    @Published var request: AppScreen?
}
