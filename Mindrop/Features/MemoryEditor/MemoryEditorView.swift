import MindropCore
import SwiftUI

struct MemoryEditorView: View {
    enum Mode {
        case create
        case edit(Memory)
    }

    let mode: Mode
    let repository: MemoryRepository

    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String
    @State private var value: String
    @State private var saveError: String?

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
                    TextField("Value", text: $value, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Saved values can show up directly in Spotlight search results, where anyone using this iPhone may see them.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
                Text(saveError ?? "")
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
            switch mode {
            case .create:
                try repository.create(keyword: keyword, value: value)
            case .edit(let memory):
                try repository.update(memory, keyword: keyword, value: value)
            }
            dismiss()
        } catch {
            saveError = String(describing: error)
        }
    }
}
