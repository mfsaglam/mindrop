import MindropCore
import SwiftUI

/// The list before anything is saved, which doubles as Mindrop's onboarding: a Spotlight
/// search drawn the way Spotlight shows a memory, three steps, and the button to start.
/// The one thing a new user needs to know is where a saved value turns up again.
///
/// Settings shows it again as How Mindrop Works, playing the user's own memories when some
/// make a good example, and without the button.
struct SpotlightGuide: View {
    private let examples: [SpotlightExample]
    private let showsOwnMemories: Bool
    private let newMemory: (() -> Void)?

    /// The empty list's guide: sample searches, and the button to save a first memory.
    init(newMemory: @escaping () -> Void) {
        examples = SpotlightExample.samples
        showsOwnMemories = false
        self.newMemory = newMemory
    }

    /// How Mindrop Works: searches for the user's own memories, the samples if none suits.
    init(memories: [Memory]) {
        let own = SpotlightExample.own(from: memories)
        examples = own.isEmpty ? SpotlightExample.samples : own
        showsOwnMemories = !own.isEmpty
        newMemory = nil
    }

    /// On iPhone Duo's inner display, the search on the leading page and what it means on the
    /// trailing one.
    var body: some View {
        FoldSpread(alignment: .center, spacing: 28, pageAlignment: .center) {
            VStack(spacing: 10) {
                SpotlightPreview(examples: examples)
                if showsOwnMemories {
                    Text("Your own memories, as Spotlight shows them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
        } secondary: {
            VStack(spacing: 8) {
                Text("One search away")
                    .font(.title2.weight(.bold))
                Text("Mindrop puts what you save into Spotlight.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                step(1, Text("Save a value under a keyword"))
                step(2, Text("Swipe down on the Home Screen"))
                step(3, Text("Type the keyword, and the value is right there"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            if let newMemory {
                Button(action: newMemory) {
                    Label("Save Your First Memory", image: "ix.add.linear")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        // The accent is black, white in dark mode: the label takes the opposite.
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }

    private func step(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(number, format: .number)
                .font(.subheadline.weight(.bold))
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
            text
        }
    }
}

/// One search the guide plays: the keyword typed, and the result Spotlight shows for it.
struct SpotlightExample {
    let keyword: String
    let value: String
    let category: MemoryCategory?

    /// Everyday searches for someone who has saved nothing yet. Sample user content stays
    /// in English in every language.
    static let samples = [
        SpotlightExample(keyword: "parking", value: "Level B2 blue zone 147", category: .vehicle),
        SpotlightExample(keyword: "gym locker", value: "4826", category: .code),
        SpotlightExample(keyword: "shoe size", value: "EU 42", category: .people),
        SpotlightExample(keyword: "bike lock", value: "7391", category: .code),
        SpotlightExample(keyword: "printer ink", value: "305XL black", category: .home),
    ]

    /// Up to five of the user's memories, in the order given, that make a good example:
    /// Spotlight shows their value (a sensitive one shows a lock instead), and the keyword
    /// fits the search field and the result fits a card on one or two lines. Expired and
    /// deleted memories are not in Spotlight, so callers pass live ones.
    static func own(from memories: [Memory]) -> [SpotlightExample] {
        memories
            .filter { memory in
                !memory.isSensitive && memory.keyword.count <= 20 && memory.value.count <= 40
                    && !memory.value.contains(where: \.isNewline)
            }
            .prefix(5)
            .map { SpotlightExample(keyword: $0.keyword, value: $0.value, category: $0.category?.category) }
    }
}

/// Alternating example searches, as Spotlight draws a Mindrop memory: the category's
/// icon, then value · keyword.
private struct SpotlightPreview: View {
    /// Never empty, and fixed for the preview's lifetime: the animation steps through them.
    let examples: [SpotlightExample]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var exampleIndex = 0
    @State private var typedCharacterCount = 0
    @State private var showsResult = false

    private var example: SpotlightExample { examples[exampleIndex] }
    private var keyword: String { example.keyword }
    private var value: String { example.value }
    private var animatesSearch: Bool {
        !reduceMotion && !voiceOverEnabled && scenePhase == .active
    }
    private var visibleKeyword: String {
        animatesSearch ? String(keyword.prefix(typedCharacterCount)) : keyword
    }
    private var resultIsVisible: Bool { !animatesSearch || showsResult }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image("ix.search-normal.linear")
                    .foregroundStyle(.secondary)
                // The cursor follows the last letter closely, as a real text field's does.
                HStack(spacing: 1) {
                    Text(verbatim: visibleKeyword)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.tint)
                        .frame(width: 2, height: 20)
                        .opacity(animatesSearch && typedCharacterCount < keyword.count ? 1 : 0)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)

            ZStack(alignment: .topLeading) {
                ForEach(examples.indices, id: \.self) { index in
                    resultCard(for: examples[index])
                        .opacity(index == exampleIndex ? 1 : 0)
                }
            }
            // Reserve enough space for every example, even when its card is hidden.
            .opacity(resultIsVisible ? 1 : 0)
            .offset(y: resultIsVisible ? 0 : 8)
        }
        .padding(18)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 34, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Example: searching “\(keyword)” in Spotlight shows “\(value)”."))
        .task(id: animatesSearch) {
            await animateSearch()
        }
    }

    private func resultCard(for example: SpotlightExample) -> some View {
        HStack(spacing: 12) {
            CategoryTile(category: example.category, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(example.value) · \(example.keyword)")
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "Mindrop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(.category(example.category), in: .rect(cornerRadius: 22, style: .continuous))
    }

    @MainActor
    private func animateSearch() async {
        guard animatesSearch else { return }
        exampleIndex = 0
        typedCharacterCount = 0
        showsResult = false

        do {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(400))
                for count in 1...keyword.count {
                    try Task.checkCancellation()
                    typedCharacterCount = count
                    try await Task.sleep(for: .milliseconds(110))
                }
                try await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeOut(duration: 0.35)) {
                    showsResult = true
                }

                // Give the result time to be read before clearing the search.
                try await Task.sleep(for: .seconds(3))
                withAnimation(.easeIn(duration: 0.25)) {
                    showsResult = false
                }
                try await Task.sleep(for: .milliseconds(250))
                for count in stride(from: keyword.count - 1, through: 0, by: -1) {
                    try Task.checkCancellation()
                    typedCharacterCount = count
                    try await Task.sleep(for: .milliseconds(55))
                }
                try Task.checkCancellation()
                exampleIndex = (exampleIndex + 1) % examples.count
            }
        } catch {
            // Leaving the screen, backgrounding or changing accessibility stops the loop.
        }
    }
}
