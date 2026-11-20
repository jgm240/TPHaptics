import SwiftUI

struct NotificationsView: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Screen {
            // Master switch
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardTitle(title: "Buzz on notifications",
                                  subtitle: "Plays a pattern whenever a banner appears. Notifications silenced by Focus won't buzz.")
                        Spacer()
                        Toggle("", isOn: $model.notifyEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    HStack {
                        PatternPicker(title: "Default pattern", name: $model.notifyPatternName)
                            .frame(maxWidth: 320)
                        Button("Preview") { model.previewNotificationBuzz() }
                        Spacer()
                        Pill(text: model.notifyStatus,
                             tint: model.notifyStatus.hasPrefix("Watching") ? .green : .secondary)
                    }
                }
            }

            // Permission
            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.accessibilityTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.accessibilityTrusted ? "Accessibility access granted" : "Accessibility access needed")
                            .font(.headline)
                        Hint("macOS has no public way to see other apps' notifications, so TPHaptics watches Notification Center's banners through the Accessibility API.")
                        if !model.accessibilityTrusted {
                            HStack {
                                Button("Request Access…") { model.requestAccessibility() }
                                Button("Open Settings") { model.openAccessibilitySettings() }
                            }
                        }
                    }
                }
            }

            // Rules
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardTitle(title: "Rules",
                                  subtitle: "Give an app or sender its own feel. The first matching rule wins; otherwise the default plays.")
                        Spacer()
                        Button {
                            model.rules.append(NotificationRule(match: "", patternName: Presets.knock.name))
                        } label: { Label("Add rule", systemImage: "plus") }
                    }
                    if model.rules.isEmpty {
                        Hint("No rules yet. Add one, or press “Make rule” on a recent notification below.")
                    }
                    ForEach($model.rules) { $rule in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $rule.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                            TextField("App or text contains…", text: $rule.match)
                                .textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            PatternPicker(title: "", name: $rule.patternName, allowSilent: true)
                                .labelsHidden().frame(width: 190)
                            Button {
                                model.previewRule(rule)
                            } label: { Image(systemName: "play.fill") }
                            .help("Preview")
                            Button(role: .destructive) {
                                model.rules.removeAll { $0.id == rule.id }
                            } label: { Image(systemName: "trash") }
                            .help("Delete rule")
                        }
                    }
                }
            }

            // Recent
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle(title: "Recent notifications",
                              subtitle: "What TPHaptics read from each banner. Use this to see what text a rule can match.")
                    if model.recentNotifications.isEmpty {
                        Hint("Nothing yet. Send a test notification below.")
                    }
                    ForEach(model.recentNotifications) { n in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.texts.first ?? "(no text found)").font(.callout.weight(.medium))
                                Text(n.texts.dropFirst().joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if let m = n.matchedRule { Pill(text: "rule: \(m)", tint: .green) }
                            if let first = n.texts.first, n.matchedRule == nil {
                                Button("Make rule") {
                                    model.rules.append(NotificationRule(match: first, patternName: Presets.knock.name))
                                }
                            }
                        }
                        Divider()
                    }
                }
            }

            HStack {
                Button("Send Test Notification") { model.sendTestNotification() }
                if let m = model.testNotificationMessage { Text(m).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }
}
