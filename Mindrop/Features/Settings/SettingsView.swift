import MindropCore
import SwiftUI

/// Preferences that only the app reads, so they live in the app's own defaults rather
/// than the App Group.
enum Preference {
    static let groupsByCategory = "groupsByCategory"
    static let syncsWithICloud = "syncsWithICloud"
    static let automaticDriveBackup = "automaticDriveBackup"
    #if os(macOS)
    static let showsMenuBarIcon = "showsMenuBarIcon"
    #endif
}

struct SettingsView: View {
    let repository: MemoryRepository
    let session: MindropSession

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif
    @AppStorage(Preference.groupsByCategory) private var groupsByCategory = true
    @AppStorage(Preference.syncsWithICloud) private var syncsWithICloud = true
    #if os(macOS)
    @AppStorage(Preference.showsMenuBarIcon) private var showsMenuBarIcon = false
    #endif

    var body: some View {
        NavigationStack {
            MemorySheetForm {
                #if os(macOS)
                Section {
                    Toggle("Show Mindrop in Menu Bar", isOn: $showsMenuBarIcon)
                }
                #endif
                Section {
                    Toggle("Group by Category", isOn: $groupsByCategory)
                } footer: {
                    Text("Show memories in sections by category. Turn this off for a single list, most recent first.")
                }

                Section {
                    Toggle("iCloud Sync", isOn: $syncsWithICloud)
                        .onChange(of: syncsWithICloud) { session.syncPreferenceChanged() }
                    NavigationLink("iCloud Backup") {
                        ICloudBackupsView(repository: repository, drive: session.driveBackup)
                            .settingsBackButton()
                    }
                } footer: {
                    Text("Keeps your memories the same on every device signed in to your iCloud account. Keywords and values are end-to-end encrypted.")
                }

                Section {
                    NavigationLink("How Mindrop Works") {
                        HowMindropWorksView(repository: repository)
                            .settingsBackButton()
                    }
                }

                Section {
                    Link("Privacy Policy", destination: URL(string: "https://mfsaglam.github.io/mindrop/privacy.html")!)
                    Link("Terms of Use", destination: URL(string: "https://mfsaglam.github.io/mindrop/terms.html")!)
                    Link("Support", destination: URL(string: "https://mfsaglam.github.io/mindrop/support.html")!)
                }

                #if DEBUG
                Section {
                    if let categorizationLog = session.categorizationLog {
                        NavigationLink {
                            CategorizationLogView(log: categorizationLog, repository: repository)
                                .settingsBackButton()
                        } label: {
                            Label { Text(verbatim: "Apple Intelligence Log") } icon: { Image(systemName: "ladybug") }
                        }
                    }
                    NavigationLink {
                        SpotlightExperimentsView(repository: repository, session: session)
                            .settingsBackButton()
                    } label: {
                        Label { Text(verbatim: "Spotlight Experiments") } icon: { Image(systemName: "magnifyingglass") }
                    }
                } header: {
                    Text(verbatim: "Debug")
                }
                #endif
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            #if os(macOS)
            .formStyle(.grouped)
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }
}

extension View {
    @ViewBuilder
    func settingsBackButton() -> some View {
        #if os(macOS)
        modifier(SettingsBackButton())
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct SettingsBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back")
                }
            }
    }
}
#endif
