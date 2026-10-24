import SwiftUI

/// The grid of memory cards in the list and in Recently Deleted: as many columns as fit, never
/// fewer than two. Where iPhone Duo's inner display folds down the middle, Apple's advice for
/// grids: an even number, the same on each page, with a wider gap at the fold, so no card
/// lies across it. Two columns, as before, on every other iPhone.
struct CardGrid<Content: View>: View {
    @ViewBuilder var content: Content

    private let spacing: CGFloat = 12
    /// Narrower cards would cut most values short. Grows with the text size.
    @ScaledMetric(relativeTo: .headline) private var minimumCardWidth: CGFloat = 160
    @State private var space = Space(width: 0, fold: nil)

    var body: some View {
        let minimumCardWidth = minimumCardWidth
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content
        }
        // Measured on the full-width frame, which the columns inside it can't change.
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Space.self) { proxy in
            Space(width: proxy.size.width, fold: Fold(in: proxy, minimumPage: minimumCardWidth))
        } action: { space = $0 }
    }

    private var columns: [GridItem] {
        guard let fold = space.fold else {
            let count = max(2, Int((space.width + spacing) / (minimumCardWidth + spacing)))
            return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
        }
        // As many as fit on the narrower page, the same on both, so rows line up across.
        let leadingPage = fold.leading
        let trailingPage = space.width - fold.trailing
        let perPage = max(1, Int((min(leadingPage, trailingPage) + spacing) / (minimumCardWidth + spacing)))
        let leadingWidth = (leadingPage - CGFloat(perPage - 1) * spacing) / CGFloat(perPage)
        // Fixed on the leading page, so the gap lands on the fold; flexible on the trailing
        // page, which takes the rest. A vertical toolbar on one side makes them differ.
        let leading = (1...perPage).map { column in
            GridItem(.fixed(leadingWidth), spacing: column == perPage ? fold.trailing - fold.leading : spacing)
        }
        let trailing = Array(repeating: GridItem(.flexible(), spacing: spacing), count: perPage)
        return leading + trailing
    }
}

/// The width a `CardGrid` has, and the fold down it on iPhone Duo.
private nonisolated struct Space: Equatable, Sendable {
    let width: CGFloat
    let fold: Fold?
}
