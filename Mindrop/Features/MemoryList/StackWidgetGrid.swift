#if os(iOS)
import MindropWidgetData
import SwiftUI

/// The content of the medium Home Screen widget and its preview in Mindrop.
/// The caller supplies the ordered memories and the surrounding surface.
struct StackWidgetGrid: View {
    let records: [StackWidgetSnapshot.Record]
    var fillsAvailableHeight = false

    private static let columnCount = 2
    private static let rowCount = 3
    static let capacity = columnCount * rowCount

    static var background: LinearGradient {
        LinearGradient(
            colors: [Color(.stackPreviewTop), Color(.stackPreviewBottom)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            if fillsAvailableHeight {
                GeometryReader { geometry in
                    grid(rowHeight: geometry.size.height / CGFloat(Self.rowCount))
                }
            } else {
                grid(rowHeight: nil)
            }
        }
        .padding(8)
    }

    private func grid(rowHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<Self.columnCount, id: \.self) { column in
                        cell(at: row * Self.columnCount + column, rowHeight: rowHeight)
                    }
                }
                .overlay(alignment: .top) {
                    if row > 0 {
                        divider.frame(height: 1)
                    }
                }
            }
        }
        .overlay {
            divider.frame(width: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.14))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func cell(at index: Int, rowHeight: CGFloat?) -> some View {
        Group {
            if records.indices.contains(index) {
                let record = records[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.keyword)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(record.value)
                        .font(rowHeight == nil ? .headline : .subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: rowHeight == nil)
                .padding(.horizontal, 10)
                .padding(.vertical, rowHeight == nil ? 6 : 2)
                .accessibilityElement(children: .combine)
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .frame(height: rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: rowHeight == nil ? 54 : nil, alignment: .leading)
    }
}
#endif
