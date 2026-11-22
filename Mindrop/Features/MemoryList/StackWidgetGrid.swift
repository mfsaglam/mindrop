import MindropCore
import SwiftUI

/// The content of the medium Home Screen widget and its preview in Mindrop.
/// The caller supplies the ordered memories and the surrounding surface.
struct StackWidgetGrid: View {
    let memories: [Memory]

    private static let columns = [
        GridItem(.flexible(minimum: 0), spacing: 0),
        GridItem(.flexible(minimum: 0), spacing: 0)
    ]
    private static let capacity = 6

    var body: some View {
        let items = Array(memories.prefix(Self.capacity))
        LazyVGrid(columns: Self.columns, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, memory in
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 54, maxHeight: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    if index >= Self.columns.count {
                        Rectangle().fill(.primary.opacity(0.14)).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .leading) {
                    if index % Self.columns.count != 0 {
                        Rectangle().fill(.primary.opacity(0.14)).frame(width: 1)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(8)
    }
}
