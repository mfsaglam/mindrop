#if os(iOS)
import MindropCore
import SwiftUI

/// Where reading an image's lines has got to.
public enum ImageLinesState: Equatable, Sendable {
    case none
    case reading
    case read([String])
}

/// The lines read from an image, as pills to tap into the details.
///
/// A picked pill stays where it is, filled and ticked, so the same tap undoes it. Whether a
/// pill is picked comes from the details themselves, so editing them by hand keeps the
/// pills honest. Shared by the share sheet's form and the app's editor.
public struct ImageLinesSection: View {
    /// Pills shown before Show All; a screenshot can hold dozens.
    private static let linesShownAtFirst = 12

    let state: ImageLinesState
    @Binding var value: String
    @State private var showsAllLines = false

    public init(state: ImageLinesState, value: Binding<String>) {
        self.state = state
        self._value = value
    }

    public var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .reading:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    localized("Reading the image…")
                }
                .foregroundStyle(.secondary)
            } header: {
                localized("From the Image")
            }
        case .read(let lines) where lines.isEmpty:
            Section {
                localized("No text found in the image.")
                    .foregroundStyle(.secondary)
            } header: {
                localized("From the Image")
            }
        case .read(let lines):
            Section {
                let shown = showsAllLines ? lines : Array(lines.prefix(Self.linesShownAtFirst))
                FlowLayout(spacing: 8) {
                    ForEach(shown, id: \.self) { line in
                        LinePill(line: line, isPicked: ImageText.details(value, contain: line)) {
                            value = ImageText.toggling(line, in: value)
                        }
                    }
                }
                .padding(.vertical, 4)
                if shown.count < lines.count {
                    Button { showsAllLines = true } label: { localized("Show All") }
                }
            } header: {
                localized("From the Image")
            } footer: {
                localized("Tap the lines to put in the details.")
            }
        }
    }

    private func localized(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module)
    }
}

/// One line read from the image. Long lines wrap to two lines inside the pill.
private struct LinePill: View {
    let line: String
    let isPicked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                if isPicked {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(line)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline)
            // Inverted when picked, like the app's Paste button, so it reads in light and
            // dark mode whatever the accent colour.
            .foregroundStyle(isPicked ? Color(.systemBackground) : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                // A capsule while the pill is one line, a rounded card once it wraps.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPicked ? Color.primary : Color(.tertiarySystemFill))
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3, bounce: 0.35), value: isPicked)
        .sensoryFeedback(.selection, trigger: isPicked)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// Lays its subviews out left to right, wrapping onto new rows like words in a paragraph.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
#endif
