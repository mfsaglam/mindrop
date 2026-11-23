import Foundation
import MindropWidgetData
import SwiftUI
import WidgetKit

struct HomeScreenStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StackWidgetSnapshot.homeScreenKind, provider: HomeScreenStackProvider()) { entry in
            HomeScreenStackContent(records: entry.records)
                .widgetURL(StackWidgetSnapshot.stackURL)
                .containerBackground(for: .widget) { StackWidgetGrid.background }
        }
        .configurationDisplayName("Stack")
        .description("Keep memories from your Stack on the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct HomeScreenStackEntry: TimelineEntry {
    let date: Date
    let records: [StackWidgetSnapshot.Record]
}

private struct HomeScreenStackProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeScreenStackEntry {
        HomeScreenStackEntry(date: .now, records: examples(for: context.family))
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeScreenStackEntry) -> Void) {
        let now = Date.now
        let records = context.isPreview
            ? examples(for: context.family)
            : storedSnapshot().visibleRecords(at: now, capacity: capacity(for: context.family))
        completion(HomeScreenStackEntry(date: now, records: records))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeScreenStackEntry>) -> Void) {
        let timeline = storedSnapshot().displayTimeline(startingAt: .now, capacity: capacity(for: context.family))
        completion(Timeline(
            entries: timeline.frames.map { HomeScreenStackEntry(date: $0.date, records: $0.records) },
            policy: timeline.refreshAt.map { .after($0) } ?? .never
        ))
    }

    private func storedSnapshot() -> StackWidgetSnapshot {
        StackWidgetSnapshot.read(from: StackWidgetSnapshot.fileURL) ?? StackWidgetSnapshot(records: [])
    }

    private func capacity(for family: WidgetFamily) -> Int {
        family == .systemSmall ? 1 : StackWidgetGrid.capacity
    }

    private func examples(for family: WidgetFamily) -> [StackWidgetSnapshot.Record] {
        let parking = StackWidgetSnapshot.Record(keyword: String(localized: "Parking"), value: "B2 · 147")
        if family == .systemSmall { return [parking] }
        return [
            .init(keyword: String(localized: "Departure Gate"), value: "C24"),
            .init(keyword: String(localized: "Seat"), value: "18A"),
            parking,
            .init(keyword: String(localized: "Room"), value: "412"),
            .init(keyword: String(localized: "Printer Ink"), value: "305XL"),
            .init(keyword: String(localized: "Shoe Size"), value: "EU 42"),
        ]
    }
}

private struct HomeScreenStackContent: View {
    let records: [StackWidgetSnapshot.Record]

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        if let first = records.first {
            if family == .systemSmall {
                ViewThatFits(in: .vertical) {
                    singleRecord(first, keywordFont: .subheadline, valueFont: .title2)
                        .fixedSize(horizontal: false, vertical: true)
                    singleRecord(first, keywordFont: .caption, valueFont: .subheadline)
                }
                .accessibilityElement(children: .combine)
                .padding(contentMargins)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .privacySensitive()
            } else {
                StackWidgetGrid(records: records, fillsAvailableHeight: true)
                    .privacySensitive()
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Label("Stack is Empty", systemImage: "square.stack")
                    .font(.headline)
                Text("Choose Memories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(2)
            .accessibilityElement(children: .combine)
            .padding(contentMargins)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func singleRecord(
        _ record: StackWidgetSnapshot.Record, keywordFont: Font, valueFont: Font
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.keyword)
                .font(keywordFont.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(record.value)
                .font(valueFont.bold())
                .monospacedDigit()
                .lineLimit(5)
                .minimumScaleFactor(0.7)
        }
    }
}
