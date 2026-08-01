import SwiftUI

struct SettingsView: View {
    let settings: CoachSettings

    var body: some View {
        List {
            Section("Coach") {
                Toggle("Speak cues", isOn: Binding(
                    get: { settings.isSpeechEnabled },
                    set: { settings.isSpeechEnabled = $0 }
                ))
                .font(.footnote)

                Picker("Provider", selection: Binding(
                    get: { settings.providerID },
                    set: { settings.providerID = $0 }
                )) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .font(.footnote)
            }

            Section {
                // Says plainly whether coaching will actually work, rather than
                // letting the athlete discover mid-run that no key is set.
                Label(
                    Secrets.hasAnyKey ? "API key configured" : "No API key — coaching disabled",
                    systemImage: Secrets.hasAnyKey ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(Secrets.hasAnyKey ? .green : .orange)

                if !Secrets.hasAnyKey {
                    Text("Add Secrets.plist to the app's Resources folder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
