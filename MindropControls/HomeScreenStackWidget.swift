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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

private enum HomeScreenStackLayout {
    case small, medium, large, extraLarge

    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemLarge: self = .large
        case .systemExtraLarge: self = .extraLarge
        default: self = .medium
        }
    }

    var featuredCount: Int {
        switch self {
        case .small, .large: 1
        case .medium: 0
        case .extraLarge: 2
        }
    }

    var gridRows: Int {
        switch self {
        case .small: 0
        case .medium: StackWidgetGrid.mediumRowCount
        case .large: 4
        case .extraLarge: 5
        }
    }

    var capacity: Int { featuredCount + StackWidgetGrid.columnCount * gridRows }
}

private struct HomeScreenStackEntry: TimelineEntry {
    let date: Date
    let records: [StackWidgetSnapshot.Record]
}

private struct HomeScreenStackProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeScreenStackEntry {
        HomeScreenStackEntry(date: .now, records: examples(for: HomeScreenStackLayout(context.family)))
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeScreenStackEntry) -> Void) {
        let now = Date.now
        let layout = HomeScreenStackLayout(context.family)
        let records = context.isPreview
            ? examples(for: layout)
            : storedSnapshot().visibleRecords(at: now, capacity: layout.capacity)
        completion(HomeScreenStackEntry(date: now, records: records))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeScreenStackEntry>) -> Void) {
        let layout = HomeScreenStackLayout(context.family)
        let timeline = storedSnapshot().displayTimeline(startingAt: .now, capacity: layout.capacity)
        completion(Timeline(
            entries: timeline.frames.map { HomeScreenStackEntry(date: $0.date, records: $0.records) },
            policy: timeline.refreshAt.map { .after($0) } ?? .never
        ))
    }

    private func storedSnapshot() -> StackWidgetSnapshot {
        StackWidgetSnapshot.read(from: StackWidgetSnapshot.fileURL) ?? StackWidgetSnapshot(records: [])
    }

    private func examples(for layout: HomeScreenStackLayout) -> [StackWidgetSnapshot.Record] {
        typealias Record = StackWidgetSnapshot.Record
        let parking = Record(keyword: String(localized: "Parking"), value: "B2 · 147")
        if layout == .small { return [parking] }

        let gate = Record(keyword: String(localized: "Departure Gate"), value: "C24")
        let seat = Record(keyword: String(localized: "Seat"), value: "18A")
        let room = Record(keyword: String(localized: "Room"), value: "412")
        let ink = Record(keyword: String(localized: "Printer Ink"), value: "305XL")
        let shoes = Record(keyword: String(localized: "Shoe Size"), value: "EU 42")
        if layout == .medium { return [gate, seat, parking, room, ink, shoes] }

        let records: [Record] = [
            .init(keyword: parking.keyword, value: String(localized: "B2 · Blue zone\nBy the elevator · 147")),
            gate, seat, room,
            .init(keyword: String(localized: "Locker"), value: "B17"),
            .init(keyword: String(localized: "Meeting"), value: "09:30"),
            ink, shoes,
            .init(keyword: String(localized: "Train Platform"), value: "4"),
            .init(keyword: String(localized: "Baggage Belt"), value: "6"),
            .init(keyword: String(localized: "Reserved Table"), value: "12"),
            .init(keyword: String(localized: "Adapter"), value: "USB-C"),
        ]
        return Array(records.prefix(layout.capacity))
    }
}

private struct HomeScreenStackContent: View {
    let records: [StackWidgetSnapshot.Record]

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let first = records.first {
            populatedLayout(HomeScreenStackLayout(family), first: first)
                .privacySensitive()
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

    @ViewBuilder
    private func populatedLayout(_ layout: HomeScreenStackLayout, first: StackWidgetSnapshot.Record) -> some View {
        switch layout {
        case .small:
            ViewThatFits(in: .vertical) {
                singleRecord(first, keywordFont: .subheadline, valueFont: .title2)
                    .fixedSize(horizontal: false, vertical: true)
                singleRecord(first, keywordFont: .caption, valueFont: .subheadline)
            }
            .accessibilityElement(children: .combine)
            .padding(contentMargins)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .medium:
            StackWidgetGrid(records: records, fillsAvailableHeight: true)
        case .large:
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    featuredRecord(first)
                        .frame(height: geometry.size.height * 0.36)
                    StackWidgetGrid.divider.frame(height: 1)
                    grid(belowFeaturedIn: layout)
                }
            }
            .padding(12)
        case .extraLarge:
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        featuredRecord(first)
                            .frame(height: geometry.size.height * 0.6)
                        StackWidgetGrid.divider.frame(height: 1)
                        if let second = records.dropFirst().first {
                            featuredRecord(second, valueFont: .largeTitle)
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                    .frame(width: geometry.size.width * 0.38)
                    StackWidgetGrid.divider.frame(width: 1)
                    grid(belowFeaturedIn: layout)
                }
            }
            .padding(12)
        }
    }

    private func grid(belowFeaturedIn layout: HomeScreenStackLayout) -> some View {
        StackWidgetGrid(
            records: Array(records.dropFirst(layout.featuredCount)),
            fillsAvailableHeight: true,
            rowCount: layout.gridRows,
            inset: 0
        )
    }

    private func featuredRecord(_ record: StackWidgetSnapshot.Record, valueFont: Font = .title) -> some View {
        let lines = record.value.split(maxSplits: 1, whereSeparator: \.isNewline)
        return VStack(alignment: .leading, spacing: 4) {
            Text(record.keyword)
                .font(.footnote.weight(.medium))
                .foregroundStyle(renderingMode == .fullColor ? Color(.stackWidgetAccent) : .secondary)
                .lineLimit(2)
            Text(lines.first.map(String.init) ?? record.value)
                .font(valueFont.bold())
                .monospacedDigit()
                .lineLimit(lines.count > 1 ? 2 : 4)
                .minimumScaleFactor(0.7)
            if lines.count > 1 {
                Text(String(lines[1]))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
