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

/// A search for "wifi" and the result it finds, as Spotlight draws a Mindrop memory: the
/// category's icon, then value · keyword. An example, so it is shown as typed in every
/// language.
private struct SpotlightPreview: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image("ix.search-normal.linear")
                    .foregroundStyle(.secondary)
                Text(verbatim: "wifi")
                RoundedRectangle(cornerRadius: 1)
                    .fill(.tint)
                    .frame(width: 2, height: 20)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)

            HStack(spacing: 12) {
                CategoryTile(category: .network, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "SuperFast2026! · wifi")
                        .font(.body.weight(.medium))
                    Text(verbatim: "Mindrop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .glassEffect(.category(.network), in: .rect(cornerRadius: 22, style: .continuous))
        }
        .padding(18)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 34, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Example: searching “wifi” in Spotlight shows the saved password."))
    }
}
