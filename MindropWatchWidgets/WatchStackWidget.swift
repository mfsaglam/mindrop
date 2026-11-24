import Foundation
import MindropWidgetData
import SwiftUI
import WidgetKit

@main
struct WatchStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StackWidgetSnapshot.watchKind, provider: WatchStackProvider()) { entry in
            if #available(watchOS 10, *) {
                WatchStackWidgetContent(records: entry.records)
                    .widgetURL(StackWidgetSnapshot.stackURL)
                    .containerBackground(for: .widget) {
                        LinearGradient(
                            colors: [Color(.stackPreviewTop), Color(.stackPreviewBottom)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
            } else {
                WatchStackWidgetContent(records: entry.records)
                    .widgetURL(StackWidgetSnapshot.stackURL)
            }
        }
        .configurationDisplayName("Stack")
        .description("See memories from your Stack on your Apple Watch.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct WatchStackEntry: TimelineEntry {
    let date: Date
    let records: [StackWidgetSnapshot.Record]
}

private struct WatchStackProvider: TimelineProvider {
    private let capacity = 2

    func placeholder(in context: Context) -> WatchStackEntry {
        WatchStackEntry(date: .now, records: [
            .init(keyword: String(localized: "Departure Gate"), value: "C24"),
            .init(keyword: String(localized: "Seat"), value: "18A"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchStackEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            let now = Date.now
            completion(WatchStackEntry(date: now, records: snapshot.visibleRecords(at: now, capacity: capacity)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchStackEntry>) -> Void) {
        let timeline = snapshot.displayTimeline(startingAt: .now, capacity: capacity)
        completion(Timeline(
            entries: timeline.frames.map { WatchStackEntry(date: $0.date, records: $0.records) },
            policy: timeline.refreshAt.map { .after($0) } ?? .never
        ))
    }

    private var snapshot: StackWidgetSnapshot {
        StackWidgetSnapshot.read(from: StackWidgetSnapshot.fileURL) ?? StackWidgetSnapshot(records: [])
    }
}

private struct WatchStackWidgetContent: View {
    let records: [StackWidgetSnapshot.Record]

    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var showsTwoRecords: Bool {
        if #available(watchOS 10, *) { return showsBackground && records.count > 1 }
        return false
    }

    var body: some View {
        Group {
            if let first = records.first {
                VStack(alignment: .leading, spacing: 2) {
                    field(first, emphasized: !showsTwoRecords)
                    if showsTwoRecords { field(records[1], emphasized: false) }
                }
                .privacySensitive()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Stack", systemImage: "square.stack")
                        .font(.headline)
                    Text("Stack is Empty")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func field(_ record: StackWidgetSnapshot.Record, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.keyword)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(record.value)
                .font(emphasized ? .title2.bold() : .headline)
                .monospacedDigit()
                .lineLimit(emphasized ? 2 : 1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }
}
