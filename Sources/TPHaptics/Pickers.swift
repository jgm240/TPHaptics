import SwiftUI

/// Picks any pattern by name: presets and the user's own patterns.
struct PatternPicker: View {
    let title: String
    @Binding var name: String
    var allowSilent = false

    var body: some View {
        Picker(title, selection: $name) {
            if allowSilent { Text("(silent)").tag(AppModel.silentName) }
            ForEach(AppModel.shared.allPatternNames, id: \.self) { Text($0).tag($0) }
        }
    }
}
