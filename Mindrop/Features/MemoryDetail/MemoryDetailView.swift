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
    @State private var changeFailed = false
    @Environment(\.self) private var environment
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
                Label("Memory Not Found", systemImage: "info.circle")
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

                if repository.isEligibleForStack(memory) {
                    stackOption(for: memory)
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
                    Label("Edit", systemImage: "pencil")
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
        .alert("Couldn’t save", isPresented: $changeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func stackOption(for memory: Memory) -> some View {
        Toggle("Show in Stack", isOn: Binding(
            get: { repository.isInStack(memory.id) },
            set: { included in
                do {
                    try repository.setStackMembership([memory.id], included: included)
                } catch {
                    changeFailed = true
                }
            }
        ))
        .toggleStyle(.switch)
        .tint(Color(.brandCobalt))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.category(category), in: .rect(cornerRadius: 32, style: .continuous))
    }

    /// Copy, in the category's colour, says "Copied" for a moment after copying.
    private func actions(for memory: Memory) -> some View {
        let copyTint = memory.category?.category.tint ?? .accentColor
        let labelColor = copyTint.contrastingForeground(in: environment)
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    copy(memory.value)
                } label: {
                    Group {
                        if didCopy {
                            Label("Copied", systemImage: "checkmark.circle")
                        } else {
                            Label("Copy", systemImage: "document.on.document")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(copyTint)

                ShareLink(item: memory.value) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .padding(6)
                }
                .buttonStyle(.glass)

                if let action = MemoryAction(memory: memory) {
                    Link(destination: action.url) {
                        Label { Text(action.title) } icon: { Image(systemName: action.symbolName) }
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

    /// The exact expiry date and the remaining time to expire or be deleted.
    @ViewBuilder
    private func expiry(for memory: Memory) -> some View {
        if let expiresAt = memory.expiresAt {
            let dateFormat = Date.FormatStyle.dateTime.day().month(.wide).year()
            let now = Date.now
            if memory.isExpired(at: now) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expired on \(expiresAt, format: dateFormat)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        ExpiryText(memory: memory, now: now)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { setExpiry(nil, for: memory) } label: { Label("Recover", systemImage: "arrow.uturn.backward") }
                        .font(.footnote.weight(.medium))
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #else
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    #endif
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expires on \(expiresAt, format: dateFormat)")
                        .font(.subheadline.weight(.medium))
                    Menu {
                        expiryActions(for: memory, expiresAt: expiresAt)
                    } label: {
                        Label {
                            Text(expiresAt, format: .relative(presentation: .named))
                        } icon: {
                            Image(systemName: "timer")
                        }
                        #if os(iOS)
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
                    .accessibilityValue(Text(expiresAt, format: .relative(presentation: .named)))
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private func expiryActions(for memory: Memory, expiresAt: Date) -> some View {
        Button {
            setExpiry(expiresAt.addingTimeInterval(24 * 60 * 60), for: memory)
        } label: {
            Label("1 More Day", systemImage: "plus")
        }
        Button {
            setExpiry(expiresAt.addingTimeInterval(7 * 24 * 60 * 60), for: memory)
        } label: {
            Label("1 More Week", systemImage: "plus")
        }
        #if os(macOS)
        Divider()
        #endif
        Button { setExpiry(nil, for: memory) } label: {
            Label("Keep Forever", systemImage: "infinity")
        }
    }

    private func setExpiry(_ expiresAt: Date?, for memory: Memory) {
        do {
            try repository.setExpiry(expiresAt, for: memory)
        } catch {
            changeFailed = true
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
            Label("Automatic", systemImage: "sparkles").tag(MemoryCategory?.none)
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
                changeFailed = true
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
