import MindropCore
import SwiftUI

/// Save-only form: the shared text arrives as the value, the user adds a keyword.
struct ShareView: View {
    let loadSharedValue: () async -> String?
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var keyword = ""
    @State private var value = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !isSaving && (try? MemoryNormalizer.validate(keyword: keyword, value: value)) != nil
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
            .navigationTitle("Save to Mindrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
            .alert("Couldn’t save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            if let shared = await loadSharedValue(), value.isEmpty {
                value = shared
            }
        }
    }

    private func save() async {
        isSaving = true
        do {
            let repository = try MemoryRepository.live()
            try repository.load()
            try await repository.createAwaitingIndex(keyword: keyword, value: value)
            onFinish()
        } catch {
            errorMessage = String(describing: error)
            isSaving = false
        }
    }
}
