import MindropCore
import SwiftUI

/// The list before anything is saved, which doubles as Mindrop's onboarding: a Spotlight
/// search drawn the way Spotlight shows a memory, three steps, and the button to start.
/// The one thing a new user needs to know is where a saved value turns up again.
struct SpotlightGuide: View {
    let newMemory: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            SpotlightPreview()
                .padding(.top, 12)

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

/// Alternating example searches, as Spotlight draws a Mindrop memory: the category's
/// icon, then value · keyword. Sample user content stays in English in every language.
private struct SpotlightPreview: View {
    private struct Example {
        let keyword: String
        let value: String
        let category: MemoryCategory
    }

    private static let examples = [
        Example(keyword: "parking", value: "Level B2 blue zone 147", category: .vehicle),
        Example(keyword: "gym locker", value: "4826", category: .code),
        Example(keyword: "shoe size", value: "EU 42", category: .people),
        Example(keyword: "bike lock", value: "7391", category: .code),
        Example(keyword: "printer ink", value: "305XL black", category: .home),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var exampleIndex = 0
    @State private var typedCharacterCount = 0
    @State private var showsResult = false

    private var example: Example { Self.examples[exampleIndex] }
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
                ForEach(Self.examples.indices, id: \.self) { index in
                    resultCard(for: Self.examples[index])
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

    private func resultCard(for example: Example) -> some View {
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
                exampleIndex = (exampleIndex + 1) % Self.examples.count
            }
        } catch {
            // Leaving the screen, backgrounding or changing accessibility stops the loop.
        }
    }
}
