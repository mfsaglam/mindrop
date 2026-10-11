import MindropCore
import SwiftUI
import UIKit

struct MemoryDetailView: View {
    let repository: MemoryRepository
    let memoryID: UUID

    @State private var isEditing = false
    @State private var didCopy = false
    @State private var copyCount = 0

    private var memory: Memory? {
        repository.memory(id: memoryID)
    }

    var body: some View {
        if let memory {
            content(for: memory)
        } else {
            // Reachable from a Spotlight result whose memory has since been deleted.
            ContentUnavailableView {
                Label("Memory Not Found", systemImage: "questionmark.circle")
            } description: {
                Text("This memory is no longer saved in Mindrop.")
            }
        }
    }

    private func content(for memory: Memory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(memory.keyword)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    copy(memory.value)
                } label: {
                    Text(memory.value)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Value")
                .accessibilityValue(memory.value)
                .accessibilityHint("Double tap to copy to the clipboard")

                // The blank placeholder keeps the layout from jumping, and must not
                // be looked up for translation.
                Group {
                    if didCopy {
                        Text("Copied")
                    } else {
                        Text(verbatim: " ")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(!didCopy)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No navigation title: the keyword is already on screen, above the value.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            MemoryEditorView(mode: .edit(memory), repository: repository)
        }
        .sensoryFeedback(.success, trigger: copyCount)
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        copyCount += 1
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { didCopy = false }
        }
    }
}
