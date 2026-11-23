import MindropWidgetData
import SwiftUI
import UIKit

struct LockScreenStackContent: View {
    typealias Record = StackWidgetSnapshot.Record

    let records: [Record]
    let layout: LockScreenStackLayout

    private let columnSpacing: CGFloat = 8

    var body: some View {
        Group {
            if let first = records.first {
                arrangement(first: first)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Stack", systemImage: "square.stack")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Stack is Empty")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(2)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
    }

    @ViewBuilder
    private func arrangement(first: Record) -> some View {
        if records.count == 1 {
            cell(first, valueSize: 28, keywordSize: 11, valueLines: 2)
        } else {
            switch layout {
            case .focus:
                cell(first, valueSize: 28, keywordSize: 11, valueLines: 2)
            case .stacked:
                VStack(spacing: 4) {
                    ForEach(records.indices, id: \.self) { index in
                        cell(records[index], valueSize: 16)
                    }
                }
            case .sideBySide:
                columns(records.prefix(2), valueSize: 21)
                    .overlay { separator.frame(width: 1) }
            case .priority:
                featured(first)
            case .grid:
                GeometryReader { geometry in
                    Group {
                        if fitsGrid(first.value, in: geometry.size.width) {
                            VStack(spacing: 4) {
                                columns(records.prefix(2), valueSize: 15)
                                if records.count > 2 {
                                    columns(records.dropFirst(2).prefix(2), valueSize: 15)
                                }
                            }
                        } else {
                            featured(first)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func featured(_ first: Record) -> some View {
        VStack(spacing: 2) {
            cell(first, valueSize: 21, keywordSize: 10)
            separator.frame(height: 1)
            columns(records.dropFirst().prefix(2), valueSize: 14)
        }
    }

    private func columns(_ items: ArraySlice<Record>, valueSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(items.indices, id: \.self) { index in
                cell(items[index], valueSize: valueSize)
            }
            if items.count == 1 {
                Color.clear
                    .frame(height: 0)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private func cell(
        _ record: Record, valueSize: CGFloat, keywordSize: CGFloat = 10, valueLines: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.keyword)
                .font(.system(size: keywordSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(record.value)
                .font(.system(size: valueSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(valueLines)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }

    private var separator: some View {
        Rectangle()
            .fill(.primary.opacity(0.24))
            .accessibilityHidden(true)
    }

    private func fitsGrid(_ value: String, in width: CGFloat) -> Bool {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 15 * 0.8, weight: .bold)
        let columnWidth = (width - columnSpacing) / 2
        return !value.contains(where: \.isNewline) && value.size(withAttributes: [.font: font]).width <= columnWidth
    }
}
