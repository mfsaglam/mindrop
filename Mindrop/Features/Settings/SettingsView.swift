import MindropCore
import SwiftUI

/// Preferences that only the app reads, so they live in the app's own defaults rather
/// than the App Group.
enum Preference {
    static let groupsByCategory = "groupsByCategory"
    static let syncsWithICloud = "syncsWithICloud"
}

struct SettingsView: View {
    let repository: MemoryRepository
    let categorizationLog: CategorizationLog?
    let session: MindropSession

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @AppStorage(Preference.syncsWithICloud) private var syncsWithICloud = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Group by Category", isOn: $groupsByCategory)
                } footer: {
                    Text("Show memories in sections by category. Turn this off for a single list, most recent first.")
                }

                Section {
                    Toggle("iCloud Sync", isOn: $syncsWithICloud)
                        .onChange(of: syncsWithICloud) { session.syncPreferenceChanged() }
                } footer: {
                    Text("Keeps your memories the same on every device signed in to your iCloud account. Keywords and values are end-to-end encrypted.")
                }

                #if DEBUG
                Section {
                    if let categorizationLog {
                        NavigationLink {
                            CategorizationLogView(log: categorizationLog, repository: repository)
                        } label: {
                            Label { Text(verbatim: "Apple Intelligence Log") } icon: { Image(systemName: "ladybug") }
                        }
                    }
                    NavigationLink {
                        SpotlightExperimentsView(repository: repository, session: session)
                    } label: {
                        Label { Text(verbatim: "Spotlight Experiments") } icon: { Image(systemName: "magnifyingglass") }
                    }
                } header: {
                    Text(verbatim: "Debug")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
