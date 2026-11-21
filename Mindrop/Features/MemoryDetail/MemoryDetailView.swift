import MindropCore
import SwiftUI

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
                Label("Memory Not Found", image: "ix.info-circle.linear")
            } description: {
                Text("This memory is no longer saved in Mindrop.")
            }
        }
    }

    /// The keyword above one glass card holding the value, touched with the category's
    /// colour, and Copy, Share and the value's own action below it. On iPhone Duo's inner
    /// display, the value on the leading page and what to do with it on the trailing one.
    private func content(for memory: Memory) -> some View {
        ScrollView {
            FoldSpread(spacing: 18) {
                header(for: memory)

                expiry(for: memory)

                valueCard(for: memory)
            } secondary: {
                if sensitiveAccess.canShow(memory) {
                    actions(for: memory)
                }

                // Not while expired: it has already left Spotlight.
                if !memory.isExpired(at: .now) {
                    let line = SpotlightAttributesFactory.make(for: memory).displayName
                    Text("Shows in Spotlight as “\(line)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            .padding()
        }
        // No navigation title: the keyword is already on screen, above the value.
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The editor shows the value, so a hidden one is unlocked first.
                Button {
                    if memory.isSensitive {
                        Task { isEditing = await sensitiveAccess.unlock() }
                    } else {
                        isEditing = true
                    }
                } label: {
                    Label("Edit", image: "ix.edit-2.linear")
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
            Text("Please try again.")
        }
    }

    private func header(for memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                CategoryTile(category: memory.category?.category)
                HStack(spacing: 4) {
                    HighlightedText(memory.keyword, query: highlight)
                        .lineLimit(2)
                    if memory.isSensitive {
                        SensitiveBadge()
                    }
                }
                .font(.headline)
                Spacer(minLength: 8)
                #if os(iOS)
                categoryMenu(for: memory)
                #endif
            }
            #if os(macOS)
            VStack(alignment: .leading, spacing: 5) {
                Text("Category")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                categoryPicker(for: memory)
                    .pickerStyle(.menu)
                    .labelsHidden()
            }
            #endif
        }
    }

    /// Tapping the value copies it too, as it always has; the button below says so.
    @ViewBuilder
    private func valueCard(for memory: Memory) -> some View {
        let category = memory.category?.category
        Group {
            if sensitiveAccess.canShow(memory) {
                VStack(alignment: .leading, spacing: 18) {
                    // Shown laid out, copied exactly as saved.
                    Button {
                        copy(memory.value)
                    } label: {
                        MemoryValueView(value: memory.value, category: category, highlight: highlight)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Value")
                    .accessibilityValue(memory.value)
                    .accessibilityHint("Double tap to copy to the clipboard")

                    if category == .network, let credentials = WiFiCredentials(value: memory.value) {
                        WiFiQRCodeView(credentials: credentials)
                    }
                }
            } else {
                // Unlocking only reveals: copying is a second, deliberate tap.
                Button {
                    Task { await sensitiveAccess.unlock() }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HiddenValue()
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Label("Show Value", image: "ix.unlock.linear")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Value")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.category(category), in: .rect(cornerRadius: 32, style: .continuous))
    }

    /// Copy, in the category's colour, says "Copied" for a moment after copying.
    private func actions(for memory: Memory) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    copy(memory.value)
                } label: {
                    Group {
                        if didCopy {
                            Label("Copied", image: "ix.tick-circle.linear")
                        } else {
                            Label("Copy", image: "ix.copy.linear")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(memory.category?.category.prefersDarkText == true ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(memory.category?.category.tint)

                ShareLink(item: memory.value) {
                    Label("Share", image: "ix.export-arrow-01.linear")
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .padding(6)
                }
                .buttonStyle(.glass)

                if let action = MemoryAction(memory: memory) {
                    Link(destination: action.url) {
                        Label { Text(action.title) } icon: { Image(action.symbolName) }
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .padding(6)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
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
                    Button { setExpiry(nil, for: memory) } label: { Label("Recover", image: "ix.undo-arrow.linear") }
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #else
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    #endif
                }
                .font(.footnote.weight(.medium))
            } else if let expiresAt = memory.expiresAt {
                Menu {
                    expiryActions(for: memory, expiresAt: expiresAt)
                } label: {
                    #if os(macOS)
                    text
                    #else
                    text
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.12), in: .capsule)
                        .foregroundStyle(.orange)
                    #endif
                }
                #if os(macOS)
                .fixedSize()
                #else
                .accessibilityLabel("Expiry")
                #endif
            }
        }
    }

    @ViewBuilder
    private func expiryActions(for memory: Memory, expiresAt: Date) -> some View {
        Button {
            setExpiry(expiresAt.addingTimeInterval(24 * 60 * 60), for: memory)
        } label: {
            Label("1 More Day", image: "ix.add.linear")
        }
        Button {
            setExpiry(expiresAt.addingTimeInterval(7 * 24 * 60 * 60), for: memory)
        } label: {
            Label("1 More Week", image: "ix.add.linear")
        }
        #if os(macOS)
        Divider()
        #endif
        Button { setExpiry(nil, for: memory) } label: {
            Label("Keep Forever", image: "ix.timer-pause.linear")
        }
    }

    private func setExpiry(_ expiresAt: Date?, for memory: Memory) {
        do {
            try repository.setExpiry(expiresAt, for: memory)
        } catch {
            categoryError = String(describing: error)
        }
    }

    #if os(iOS)
    private func categoryMenu(for memory: Memory) -> some View {
        Menu {
            categoryPicker(for: memory)
        } label: {
            // The tile beside the keyword already shows the category's symbol.
            Group {
                if let category = memory.category?.category {
                    Text(category.title)
                } else {
                    Text("No Category")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.category(memory.category?.category), in: .capsule)
        }
        .accessibilityLabel("Category")
    }
    #endif

    /// "Automatic" hands the choice back to Apple Intelligence.
    private func categoryPicker(for memory: Memory) -> some View {
        Picker("Category", selection: categoryBinding(for: memory)) {
            #if os(macOS)
            if let assignment = memory.category, assignment.source == .automatic {
                Text("\(Text("Automatic")) (\(Text(assignment.category.title)))")
                    .tag(MemoryCategory?.none)
            } else {
                Text("Automatic").tag(MemoryCategory?.none)
            }
            #else
            Label("Automatic", image: "ix.magic-star.linear").tag(MemoryCategory?.none)
            #endif
            ForEach(MemoryCategory.allCases, id: \.self) { category in
                #if os(macOS)
                Text(category.title).tag(Optional(category))
                #else
                category.menuLabel.tag(Optional(category))
                #endif
            }
        }
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
        Clipboard.copy(value)
        copyCount += 1
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { didCopy = false }
        }
    }
}
