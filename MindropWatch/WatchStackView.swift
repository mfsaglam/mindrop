import MindropWidgetData
import SwiftUI

struct WatchStackView: View {
    @ObservedObject var sender: WatchSender
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snapshot = sender.stackSnapshot ?? StackWidgetSnapshot(records: [])
        let dates = snapshot.displayTimeline(
            startingAt: .now, capacity: StackWidgetSnapshot.watchCapacity
        ).frames.map(\.date)
        NavigationStack {
            TimelineView(.explicit(dates)) { context in
                let records = snapshot.visibleRecords(
                    at: context.date, capacity: StackWidgetSnapshot.watchCapacity
                )
                if records.isEmpty {
                    Label("Stack is Empty", systemImage: "square.stack")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(records.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(records[index].keyword)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(records[index].value)
                                    .font(.headline)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .privacySensitive()
                        }
                    }
                }
            }
            .navigationTitle("Stack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
