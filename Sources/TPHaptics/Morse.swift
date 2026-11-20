import SwiftUI

enum Morse {
    static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "!": "-.-.--", "/": "-..-.", "-": "-....-", "'": ".----.",
    ]

    /// "SOS NOW" → "... --- ... / -. --- .--"
    static func encode(_ text: String) -> String {
        text.uppercased().split(separator: " ")
            .map { word in word.compactMap { table[$0] }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// Dots and dashes become short and long bursts of clicks (which also sound like beeps).
    /// Timing follows the standard: dash = 3 dots, 1 dot between symbols, 3 between letters, 7 between words.
    static func pattern(text: String, wpm: Double, burstRate: Double = 100) -> HapticPattern {
        let unit = 1.2 / max(1, wpm)
        var events: [HapticEvent] = []
        var t = 0.0
        func burst(_ units: Double) {
            let dur = units * unit
            let n = max(1, Int(dur * burstRate))
            for i in 0..<n { events.append(HapticEvent(time: t + Double(i) / burstRate, actuation: Strength.max.id)) }
            t += dur
        }
        let words = text.uppercased().split(separator: " ")
            .map { $0.compactMap { table[$0] } }
            .filter { !$0.isEmpty }
        for (wi, word) in words.enumerated() {
            for (li, letter) in word.enumerated() {
                for (si, symbol) in letter.enumerated() {
                    burst(symbol == "." ? 1 : 3)
                    if si < letter.count - 1 { t += unit }
                }
                if li < word.count - 1 { t += 3 * unit }
            }
            if wi < words.count - 1 { t += 7 * unit }
        }
        return HapticPattern(name: "Morse", detail: "", events: events, length: t)
    }
}

struct MorseView: View {
    @Binding var loop: Bool
    @ObservedObject private var player = AppModel.shared.player
    @State private var text = "HELLO WORLD"
    @State private var wpm = 15.0
    @State private var burstRate = 100.0

    var body: some View {
        let playing = player.playingName == "Morse"
        let encoded = Morse.encode(text)
        Screen {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Message", subtitle: "Letters, numbers and basic punctuation.")
                    TextField("Type something…", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                    Text(encoded.isEmpty ? "—" : encoded)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Speed").frame(width: 70, alignment: .leading)
                        Slider(value: $wpm, in: 5...30, step: 1)
                        Text("\(Int(wpm)) wpm").monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                    HStack {
                        Text("Beep pitch").frame(width: 70, alignment: .leading)
                        Slider(value: $burstRate, in: 50...150, step: 5)
                        Text("\(Int(burstRate)) /s").monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                }
            }

            HStack {
                Spacer()
                BigButton(title: playing ? "Stop" : "Send", symbol: playing ? "stop.fill" : "paperplane.fill",
                          tint: playing ? .red : .accentColor) {
                    playing ? player.stop()
                            : player.play(Morse.pattern(text: text, wpm: wpm, burstRate: burstRate), loop: loop)
                }
                .disabled(encoded.isEmpty)
            }
        }
    }
}
