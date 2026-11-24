import AppIntents
import Foundation
import MindropWidgetData
import SwiftUI
import WidgetKit

enum LockScreenStackLayout: String, AppEnum {
    case focus, stacked, sideBySide, priority, grid

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Layout")

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .focus: "Single Focus",
        .stacked: "Stacked",
        .sideBySide: "Side by Side",
        .priority: "Priority",
        .grid: "Four-Item Grid",
    ]

    var capacity: Int {
        switch self {
        case .focus: 1
        case .stacked, .sideBySide: 2
        case .priority: 3
        case .grid: 4
        }
    }
}

struct ConfigureLockScreenStack: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Stack"

    @Parameter(title: "Layout", default: .stacked)
    var layout: LockScreenStackLayout
}

struct LockScreenStackWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: StackWidgetSnapshot.lockScreenKind,
            intent: ConfigureLockScreenStack.self,
            provider: LockScreenStackProvider()
        ) { entry in
            LockScreenStackContent(records: entry.records, layout: entry.layout)
                .widgetURL(StackWidgetSnapshot.stackURL)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Stack")
        .description("See memories from your Stack on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct LockScreenStackEntry: TimelineEntry {
    let date: Date
    let layout: LockScreenStackLayout
    let records: [StackWidgetSnapshot.Record]
}

private struct LockScreenStackProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockScreenStackEntry {
        sampleEntry(layout: .stacked)
    }

    func snapshot(for configuration: ConfigureLockScreenStack, in context: Context) async -> LockScreenStackEntry {
        let layout = configuration.layout
        if context.isPreview { return sampleEntry(layout: layout) }
        let now = Date.now
        return LockScreenStackEntry(
            date: now, layout: layout, records: storedSnapshot().visibleRecords(at: now, capacity: layout.capacity)
        )
    }

    func timeline(for configuration: ConfigureLockScreenStack, in context: Context) async -> Timeline<LockScreenStackEntry> {
        let layout = configuration.layout
        let timeline = storedSnapshot().displayTimeline(startingAt: .now, capacity: layout.capacity)
        return Timeline(
            entries: timeline.frames.map { LockScreenStackEntry(date: $0.date, layout: layout, records: $0.records) },
            policy: timeline.refreshAt.map { .after($0) } ?? .never
        )
    }

    private func storedSnapshot() -> StackWidgetSnapshot {
        StackWidgetSnapshot.read(from: StackWidgetSnapshot.fileURL) ?? StackWidgetSnapshot(records: [])
    }

    private func sampleEntry(layout: LockScreenStackLayout) -> LockScreenStackEntry {
        let examples: [StackWidgetSnapshot.Record] = [
            .init(keyword: String(localized: "Departure Gate"), value: "C24"),
            .init(keyword: String(localized: "Seat"), value: "18A"),
            .init(keyword: String(localized: "Room"), value: "412"),
            .init(keyword: String(localized: "Locker"), value: "B17"),
        ]
        return LockScreenStackEntry(date: .now, layout: layout, records: Array(examples.prefix(layout.capacity)))
    }
}
