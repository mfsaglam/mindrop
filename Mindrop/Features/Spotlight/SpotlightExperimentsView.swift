#if DEBUG
import MindropCore
import SwiftUI

/// Settles on a real iPhone what the simulator cannot show, since its Spotlight drops every
/// third-party item. Each choice reindexes everything, then search in Spotlight to see.
/// Debug builds only, so it is in English and not translated.
struct SpotlightExperimentsView: View {
    let repository: MemoryRepository
    let session: MindropSession

    @State private var options = SpotlightOptions.current
    @State private var check: SpotlightCheck?
    @State private var isWorking = false
    @State private var couldNotCheck = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if isWorking {
                        ProgressView()
                    } else if couldNotCheck {
                        Text(verbatim: "Couldn’t ask")
                    } else if let check {
                        Text(verbatim: "\(check.expected - check.repaired) of \(check.expected)")
                    } else {
                        Text(verbatim: "–")
                    }
                } label: {
                    Text(verbatim: "Already in Spotlight")
                }
                if let check, check.repaired > 0 || check.removed > 0 {
                    Text(verbatim: "Put back \(check.repaired), removed \(check.removed).")
                        .foregroundStyle(.secondary)
                }
                Button { run { await runCheck() } } label: { Text(verbatim: "Check Now") }
                Button { run { await repository.reindexSpotlight() } } label: { Text(verbatim: "Reindex Everything") }
                Button(role: .destructive) {
                    run { await repository.simulateLostSpotlightIndex() }
                } label: {
                    Text(verbatim: "Empty Spotlight, as After a Restore")
                }
            } header: {
                Text(verbatim: "Index")
            } footer: {
                Text(verbatim: "Asks Spotlight what it holds for Mindrop and puts back whatever is missing or out of date. Runs by itself at every launch. To see it work: empty Spotlight, search a keyword in Spotlight (nothing), then Check Now and search again.")
            }

            Section {
                Toggle(isOn: $options.showsCategoryIcon) { Text(verbatim: "Category Icons (shipped)") }
                Toggle(isOn: $options.offersCall) { Text(verbatim: "Call Button (shipped)") }
                Toggle(isOn: $options.offersDirections) { Text(verbatim: "Directions Button") }
            } footer: {
                Text(verbatim: "Icons: each result shows its category's icon, with Mindrop's as a badge. Call: a phone number in a Contacts or Family & People memory. Directions: a place's coordinates, found through Apple Maps, so the address leaves the device. Neither button for sensitive memories. iOS may only draw the buttons after a restart.")
            }

            Section {
                if let activity = session.lastSpotlightActivity {
                    LabeledContent { Text(verbatim: activity.type) } label: { Text(verbatim: "Type") }
                    ForEach(activity.keys, id: \.self) { key in
                        Text(verbatim: key)
                            .font(.footnote.monospaced())
                    }
                } else {
                    Text(verbatim: "Nothing opened from Spotlight since launch.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(verbatim: "Last Opened from Spotlight")
            } footer: {
                Text(verbatim: "Search in Spotlight, tap a Mindrop result, come back here. If kCSSearchQueryString is listed, Spotlight passes what was typed and the memory opens with it marked.")
            }
        }
        .navigationTitle(Text(verbatim: "Spotlight Experiments"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .onChange(of: options) {
            SpotlightOptions.setCurrent(options)
            run { await repository.reindexSpotlight() }
        }
        .task { await runCheck() }
    }

    private func runCheck() async {
        let result = await repository.checkSpotlight()
        couldNotCheck = result == nil
        check = result
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}
#endif
