import MindropCore
import SwiftUI

/// The content of the medium Home Screen widget and its preview in Mindrop.
/// The caller supplies the ordered memories and the surrounding surface.
struct StackWidgetGrid: View {
    let memories: [Memory]

    private static let columnCount = 2
    private static let rowCount = 3

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<Self.columnCount, id: \.self) { column in
                        cell(at: row * Self.columnCount + column)
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
        .padding(8)
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.14))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func cell(at index: Int) -> some View {
        Group {
            if memories.indices.contains(index) {
                let memory = memories[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.keyword)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(memory.value)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(2)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }
}
