import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $appState.serverURL)

                LabeledContent("Status") {
                    Text(appState.signedIn ? "Signed in" : "Signed out")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Refresh") {
                        appState.refreshLibrary()
                    }
                    .disabled(!appState.signedIn)

                    Button("Sign Out") {
                        if appState.signOut() {
                            dismiss()
                        }
                    }
                    .disabled(!appState.signedIn)
                }
            }

            Section("Storage") {
                Stepper("Artwork cache: \(appState.cacheSizeMB) MB", value: $appState.cacheSizeMB, in: 128...8192, step: 128)

                LabeledContent("Used") {
                    Text(appState.cacheUsageText)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Refresh Size") {
                        Task {
                            await appState.refreshCacheUsage()
                        }
                    }

                    Button("Clear Cache") {
                        appState.clearCache()
                    }
                }
            }

            Section("Display") {
                Picker("Date format", selection: $appState.dateDisplayFormat) {
                    ForEach(DateDisplayFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
            }

            Section {
                LabeledContent("Version") {
                    Text("Jellia \(bundleValue(for: "CFBundleShortVersionString")) (\(bundleValue(for: "CFBundleVersion")))")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Server") {
                    Text(appState.serverInfo?.displayText ?? "Not connected")
                        .foregroundStyle(.secondary)
                }

                if appState.serverInfo?.isVerifiedVersion == false {
                    Text("Jellia tested with Jellyfin \(ServerVersion.minimumVerified.raw) and newer. Older servers may misbehave.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if appState.serverInfo == nil, let serverInfoError = appState.serverInfoError {
                    Text(serverInfoError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !appState.statusMessage.isEmpty {
                    Text(appState.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .task {
            await appState.refreshCacheUsage()
            await appState.refreshServerInfo()
        }
    }

    private func bundleValue(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "n/a"
    }
}
