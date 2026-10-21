#if DEBUG
import MindropCore
import SwiftUI

/// Debug builds only, reached from Settings. Every Apple Intelligence request this launch,
/// grouped by memory.
/// English only and verbatim, so none of it reaches the string catalog.
struct CategorizationLogView: View {
    let log: CategorizationLog
    let repository: MemoryRepository

    var body: some View {
        List {
                Section {
                    summaryRow("Requests", "\(log.entries.count)")
                    summaryRow("Memories", "\(log.byMemory.count)")
                    summaryRow("Asked the model", "\(log.entries.filter { if case .rule = $0.outcome { false } else { true } }.count)")
                    summaryRow("Failed or unparsed", "\(log.entries.filter { $0.outcome.category == nil }.count)")
                    if let average = averageModelDuration {
                        summaryRow("Average model time", average.formatted(.number.precision(.fractionLength(1))) + " s")
                    }
                }

                ForEach(log.byMemory, id: \.memoryID) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                EntryRow(entry: entry)
                            }
                        }
                    } header: {
                        HStack {
                            Text(verbatim: currentKeyword(for: group))
                            Spacer()
                            Text(verbatim: group.entries.count == 1 ? "1 request" : "\(group.entries.count) requests")
                        }
                    }
                }
            }
            .overlay {
                if log.entries.isEmpty {
                    ContentUnavailableView(
                        "No requests yet",
                        systemImage: "sparkles",
                        description: Text(verbatim: "Add or edit a memory. Requests made since launch appear here.")
                    )
                }
            }
            .navigationTitle(Text(verbatim: "Apple Intelligence"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            log.clear()
                        } label: {
                            Label { Text(verbatim: "Clear Log") } icon: { Image(systemName: "trash") }
                        }
                        Button {
                            try? repository.resetAutomaticCategories()
                        } label: {
                            Label { Text(verbatim: "Recategorise All") } icon: { Image(systemName: "arrow.clockwise") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
    }

    private var averageModelDuration: Double? {
        let timed = log.entries.filter { if case .rule = $0.outcome { false } else { true } }
        guard !timed.isEmpty else { return nil }
        return timed.map(\.duration).reduce(0, +) / Double(timed.count)
    }

    /// The memory's keyword now, or the one logged if it has since been deleted.
    private func currentKeyword(for group: (memoryID: UUID, entries: [CategorizationLog.Entry])) -> String {
        repository.memory(id: group.memoryID)?.keyword ?? (group.entries.first?.keyword ?? "") + " (deleted)"
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        LabeledContent { Text(verbatim: value) } label: { Text(verbatim: title) }
    }
}

private struct EntryRow: View {
    let entry: CategorizationLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                OutcomeLabel(outcome: entry.outcome)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let response = entry.response {
                    Text(verbatim: "“\(response)”")
                        .lineLimit(1)
                }
                Spacer()
                Text(verbatim: entry.duration.formatted(.number.precision(.fractionLength(1))) + " s")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct OutcomeLabel: View {
    let outcome: CategorizationLog.Outcome

    var body: some View {
        switch outcome {
        case .model(let category):
            Label { Text(verbatim: "\(category.rawValue)") } icon: { Image(systemName: category.symbolName).foregroundStyle(category.tint) }
        case .rule(let category):
            Label { Text(verbatim: "\(category.rawValue) · rule") } icon: { Image(systemName: category.symbolName).foregroundStyle(category.tint) }
        case .unparsed:
            Label { Text(verbatim: "unparsed reply") } icon: { Image(systemName: "questionmark.circle") }
                .foregroundStyle(.orange)
        case .failed:
            Label { Text(verbatim: "failed") } icon: { Image(systemName: "exclamationmark.triangle") }
                .foregroundStyle(.red)
        case .unavailable:
            Label { Text(verbatim: "model unavailable") } icon: { Image(systemName: "nosign") }
                .foregroundStyle(.secondary)
        }
    }
}

private struct EntryDetailView: View {
    let entry: CategorizationLog.Entry

    var body: some View {
        List {
            Section {
                OutcomeLabel(outcome: entry.outcome)
                LabeledContent { Text(entry.date, format: .dateTime) } label: { Text(verbatim: "Time") }
                LabeledContent {
                    Text(verbatim: entry.duration.formatted(.number.precision(.fractionLength(2))) + " s")
                } label: {
                    Text(verbatim: "Duration")
                }
            }
            Section { block(entry.prompt) } header: { Text(verbatim: "Prompt") }
            Section { block(entry.response ?? "—") } header: { Text(verbatim: "Raw reply") }
            switch entry.outcome {
            case .failed(let message), .unavailable(let message):
                Section { block(message) } header: { Text(verbatim: "Error") }
            default:
                EmptyView()
            }
        }
        .navigationTitle(Text(verbatim: entry.keyword))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.callout.monospaced())
            .textSelection(.enabled)
    }
}
#endif
