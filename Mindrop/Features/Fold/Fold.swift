import SwiftUI

/// Where iPhone Duo's inner display folds, down a view it crosses: where the leading page
/// ends and the trailing page starts, in the view's own coordinates, from its leading edge.
///
/// Found even while the display lies flat and the hinge has no width, so a layout split at
/// the fold keeps its shape as the device folds; only the gap at the fold grows.
nonisolated struct Fold: Equatable, Sendable {
    /// Between the pages at the least: a content margin for each.
    static let minimumGap: CGFloat = 32

    /// Where the leading page ends.
    let leading: CGFloat
    /// Where the trailing page starts.
    let trailing: CGFloat

    /// The fold down the view `proxy` measures, if both pages either side of it are at least
    /// `minimumPage` wide. Nil on every other iPhone, and on the inner display held upright,
    /// where the fold runs across the view rather than down it.
    init?(in proxy: GeometryProxy, minimumPage: CGFloat) {
        guard #available(iOS 27.1, *) else { return nil }
        let width = proxy.size.width
        // Taller than wide runs down the view; a flat hinge is a line with no width.
        guard let region = proxy.reservedRegions(kind: .division, options: .includeInactive)
            .first(where: { $0.frame.height > $0.frame.width && $0.frame.midX > 0 && $0.frame.midX < width })
        else { return nil }
        // The hinge and the margin the system keeps either side of it.
        let start = region.frame.minX - region.margins.leading
        let end = region.frame.maxX + region.margins.trailing
        let center = (start + end) / 2
        let halfGap = max(end - start, Self.minimumGap) / 2
        guard center - halfGap >= minimumPage, width - (center + halfGap) >= minimumPage else { return nil }
        leading = center - halfGap
        trailing = center + halfGap
    }
}

extension View {
    /// Keeps a full-width row, line of text or empty state on the leading page where iPhone
    /// Duo folds down the screen, so nothing is read or tapped across the fold. Unchanged on
    /// every other iPhone.
    func onLeadingPage() -> some View {
        modifier(LeadingPage())
    }
}

private struct LeadingPage: ViewModifier {
    @State private var trailingInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.trailing, trailingInset)
            // Measured on the full-width frame, which the inset inside it can't change.
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                Fold(in: proxy, minimumPage: 0).map { proxy.size.width - $0.leading } ?? 0
            } action: { trailingInset = $0 }
    }
}

/// Two parts of a screen as two pages either side of the fold on iPhone Duo's inner display,
/// like a book lying open; one above the other everywhere else, as on any other iPhone.
struct FoldSpread<Primary: View, Secondary: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat
    /// Where each page sits against the taller one, side by side.
    var pageAlignment: VerticalAlignment = .top
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    /// Pages narrower than this stay one above the other: the fold would squeeze them.
    @ScaledMetric private var minimumPageWidth: CGFloat = 300
    @State private var fold: Fold?

    var body: some View {
        // Either layout around the same two pages, so nothing in them starts over as the
        // device opens, closes or turns.
        let layout = fold.map { AnyLayout(PagesLayout(fold: $0, alignment: pageAlignment)) }
            ?? AnyLayout(VStackLayout(alignment: alignment, spacing: spacing))
        let minimumPageWidth = minimumPageWidth
        layout {
            VStack(alignment: alignment, spacing: spacing) { primary }
            VStack(alignment: alignment, spacing: spacing) { secondary }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .onGeometryChange(for: Fold?.self) { proxy in
            Fold(in: proxy, minimumPage: minimumPageWidth)
        } action: { fold = $0 }
    }
}

/// The two pages of a `FoldSpread`, each as wide as its side of the fold.
private struct PagesLayout: Layout {
    let fold: Fold
    let alignment: VerticalAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? fold.leading + fold.trailing
        let heights = zip(subviews, pages(width: width)).map { subview, page in
            subview.sizeThatFits(ProposedViewSize(width: page.width, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, page) in zip(subviews, pages(width: bounds.width)) {
            let proposal = ProposedViewSize(width: page.width, height: nil)
            let height = subview.sizeThatFits(proposal).height
            let y = alignment == .center ? (bounds.height - height) / 2 : 0
            subview.place(at: CGPoint(x: bounds.minX + page.minX, y: bounds.minY + y), proposal: proposal)
        }
    }

    private func pages(width: CGFloat) -> [(minX: CGFloat, width: CGFloat)] {
        [(0, fold.leading), (fold.trailing, width - fold.trailing)]
    }
}
