import MindropCore
import SwiftUI
import UIKit

struct MemoryDetailView: View {
    let repository: MemoryRepository
    let memoryID: UUID
    /// What was typed in Spotlight to find this memory, marked on screen. Nil when it was
    /// opened from the list, or Spotlight did not say.
    var highlight: String?

    @State private var isEditing = false
    @State private var didCopy = false
    @State private var copyCount = 0
    @State private var categoryError: String?
    @Environment(\.sensitiveAccess) private var sensitiveAccess

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
                HStack(spacing: 4) {
                    HighlightedText(memory.keyword, query: highlight)
                    if memory.isSensitive {
                        SensitiveBadge()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                categoryMenu(for: memory)

                expiry(for: memory)

                if sensitiveAccess.canShow(memory) {
                    // Shown laid out, copied exactly as saved.
                    Button {
                        copy(memory.value)
                    } label: {
                        MemoryValueView(value: memory.value, highlight: highlight)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Value")
                    .accessibilityValue(memory.value)
                    .accessibilityHint("Double tap to copy to the clipboard")
                } else {
                    // Unlocking only reveals: copying is a second, deliberate tap.
                    Button {
                        Task { await sensitiveAccess.unlock() }
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HiddenValue()
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Label("Show Value", systemImage: "lock.open")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show Value")
                }

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

                if memory.category?.category == .network, sensitiveAccess.canShow(memory),
                   let credentials = WiFiCredentials(value: memory.value) {
                    WiFiQRCodeView(credentials: credentials)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No navigation title: the keyword is already on screen, above the value.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The editor shows the value, so a hidden one is unlocked first.
                Button("Edit", systemImage: "pencil") {
                    if memory.isSensitive {
                        Task { isEditing = await sensitiveAccess.unlock() }
                    } else {
                        isEditing = true
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            MemoryEditorView(mode: .edit(memory), repository: repository)
        }
        // Opening a sensitive memory, from the list or from Spotlight, is asking to see it.
        // Opening any memory is using it, which Spotlight's ranking hears about.
        .task(id: memoryID) {
            repository.recordUse(of: memory)
            if memory.isSensitive { await sensitiveAccess.unlock() }
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .alert("Couldn’t save", isPresented: .constant(categoryError != nil)) {
            Button("OK") { categoryError = nil }
        } message: {
            Text(categoryError ?? "")
        }
    }

    /// A temporary memory says when it expires and can be kept longer; an expired one
    /// says when it will be deleted and can be recovered. Nothing for one kept forever.
    @ViewBuilder
    private func expiry(for memory: Memory) -> some View {
        if let text = ExpiryText(memory: memory) {
            if memory.isExpired(at: .now) {
                HStack {
                    text
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Recover", systemImage: "arrow.uturn.backward") { setExpiry(nil, for: memory) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
                .font(.footnote.weight(.medium))
            } else if let expiresAt = memory.expiresAt {
                Menu {
                    Button("1 More Day", systemImage: "plus") {
                        setExpiry(expiresAt.addingTimeInterval(24 * 60 * 60), for: memory)
                    }
                    Button("1 More Week", systemImage: "plus") {
                        setExpiry(expiresAt.addingTimeInterval(7 * 24 * 60 * 60), for: memory)
                    }
                    Button("Keep Forever", systemImage: "infinity") { setExpiry(nil, for: memory) }
                } label: {
                    text
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.12), in: .capsule)
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel("Expiry")
            }
        }
    }

    private func setExpiry(_ expiresAt: Date?, for memory: Memory) {
        do {
            try repository.setExpiry(expiresAt, for: memory)
        } catch {
            categoryError = String(describing: error)
        }
    }

    /// Shows the category and lets the user overrule it. "Automatic" hands the choice
    /// back to Apple Intelligence.
    private func categoryMenu(for memory: Memory) -> some View {
        Menu {
            Picker("Category", selection: categoryBinding(for: memory)) {
                Label("Automatic", systemImage: "sparkles").tag(MemoryCategory?.none)
                ForEach(MemoryCategory.allCases, id: \.self) { category in
                    category.label.tag(Optional(category))
                }
            }
        } label: {
            Group {
                if let category = memory.category?.category {
                    category.label
                } else {
                    Label("No Category", systemImage: "tag")
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((memory.category?.category.tint ?? .gray).opacity(0.15), in: .capsule)
        }
        .accessibilityLabel("Category")
    }

    /// What the picker shows as chosen: only a manual pick, so "Automatic" stays ticked
    /// while Apple Intelligence decides.
    private func categoryBinding(for memory: Memory) -> Binding<MemoryCategory?> {
        Binding {
            memory.category?.source == .manual ? memory.category?.category : nil
        } set: { category in
            do {
                try repository.setCategory(category, for: memory)
            } catch {
                categoryError = String(describing: error)
            }
        }
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
