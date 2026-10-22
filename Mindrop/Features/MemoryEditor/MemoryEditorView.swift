import MindropCore
import MindropSaveUI
import SwiftUI

struct MemoryEditorView: View {
    enum Mode {
        case create
        case edit(Memory)

        var memory: Memory? {
            if case .edit(let memory) = self { memory } else { nil }
        }
    }

    let mode: Mode
    let repository: MemoryRepository

    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String
    @State private var value: String
    @State private var lifetime: MemoryLifetime.Option
    @State private var untilDate: Date
    @State private var isSensitive: Bool
    @State private var saveError: String?
    @FocusState private var isKeywordFocused: Bool

    init(mode: Mode, repository: MemoryRepository) {
        self.mode = mode
        self.repository = repository
        switch mode {
        case .create:
            _keyword = State(initialValue: "")
            _value = State(initialValue: "")
        case .edit(let memory):
            _keyword = State(initialValue: memory.keyword)
            _value = State(initialValue: memory.value)
        }
        // An existing expiry shows as its date, so saving a text edit leaves it exactly
        // where it was.
        _isSensitive = State(initialValue: mode.memory?.isSensitive ?? false)
        let expiresAt = mode.memory?.expiresAt
        _lifetime = State(initialValue: expiresAt == nil ? .forever : .date)
        _untilDate = State(initialValue: expiresAt ?? .now.addingTimeInterval(7 * 24 * 60 * 60))
    }

    private var canSave: Bool {
        (try? MemoryNormalizer.validate(keyword: keyword, value: value)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Keyword", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isKeywordFocused)
                    TextField("Value", text: $value, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                SensitiveSection(isSensitive: $isSensitive)
                MemoryLifetimeSection(
                    option: $lifetime,
                    date: $untilDate,
                    earliestDate: mode.memory?.expiresAt.map { min($0, .now) } ?? .now
                )
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // A new memory starts with the keyboard up, so the control and the Action
            // button land the user straight in typing.
            .onAppear {
                if case .create = mode { isKeywordFocused = true }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .alert("Couldn’t save", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text("Please try again.")
            }
        }
    }

    /// A `LocalizedStringKey`, not a `String`: `navigationTitle` only localises
    /// literals, so a plain String variable would ship the English through.
    private var title: LocalizedStringKey {
        switch mode {
        case .create: "New Memory"
        case .edit: "Edit Memory"
        }
    }

    private func save() {
        do {
            let expiresAt = MemoryLifetime(lifetime, until: untilDate).expiry(from: .now)
            switch mode {
            case .create:
                try repository.create(keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive)
            case .edit(let memory):
                try repository.update(
                    memory,
                    keyword: keyword,
                    value: value,
                    expiresAt: expiresAt,
                    isSensitive: isSensitive
                )
            }
            dismiss()
        } catch {
            saveError = String(describing: error)
        }
    }
}
