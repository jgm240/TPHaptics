import SwiftUI

struct UserTap: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Double      // seconds
    var level: Int        // 1…6 → index into TrackpadActuator.ladder
}

/// A pattern made in the editor, saved to disk and usable anywhere a preset is.
struct UserPattern: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var length: Double
    var taps: [UserTap]

    var pattern: HapticPattern {
        let ladder = TrackpadActuator.ladder
        let events = taps.sorted { $0.time < $1.time }.map {
            HapticEvent(time: $0.time, actuation: ladder[min(max($0.level, 1), ladder.count) - 1])
        }
        return HapticPattern(name: name, detail: "Custom pattern", events: events, length: length)
    }
}

@MainActor
final class PatternLibrary: ObservableObject {
    static let shared = PatternLibrary()
    @Published private(set) var patterns: [UserPattern] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TPHaptics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("patterns.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([UserPattern].self, from: data) {
            patterns = list
        }
    }

    /// Adds or replaces (matching id, then name) and writes to disk.
    func save(_ p: UserPattern) {
        if let i = patterns.firstIndex(where: { $0.id == p.id })
            ?? patterns.firstIndex(where: { $0.name.caseInsensitiveCompare(p.name) == .orderedSame }) {
            var q = p; q.id = patterns[i].id
            patterns[i] = q
        } else {
            patterns.append(p)
        }
        persist()
    }

    func delete(_ id: UUID) {
        patterns.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(patterns) { try? data.write(to: fileURL, options: .atomic) }
    }

    func exportData(_ p: UserPattern) -> Data? {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(p)
    }

    func importData(_ data: Data) -> UserPattern? {
        guard var p = try? JSONDecoder().decode(UserPattern.self, from: data) else { return nil }
        p.id = UUID()
        p.taps = p.taps.map { var t = $0; t.id = UUID(); return t }
        return p
    }
}
