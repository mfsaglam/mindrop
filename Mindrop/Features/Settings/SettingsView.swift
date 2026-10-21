import MindropCore
import SwiftUI

/// Preferences that only the app reads, so they live in the app's own defaults rather
/// than the App Group.
enum Preference {
    static let groupsByCategory = "groupsByCategory"
}

struct SettingsView: View {
    let repository: MemoryRepository
    let categorizationLog: CategorizationLog?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Group by Category", isOn: $groupsByCategory)
                } footer: {
                    Text("Show memories in sections by category. Turn this off for a single list, most recent first.")
                }

                #if DEBUG
                if let categorizationLog {
                    Section {
                        NavigationLink {
                            CategorizationLogView(log: categorizationLog, repository: repository)
                        } label: {
                            Label { Text(verbatim: "Apple Intelligence Log") } icon: { Image(systemName: "ladybug") }
                        }
                    } header: {
                        Text(verbatim: "Debug")
                    }
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
