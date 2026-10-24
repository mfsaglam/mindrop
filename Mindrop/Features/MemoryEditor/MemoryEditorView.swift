import MindropCore
import MindropSaveUI
import SwiftUI

struct MemoryEditorView: View {
    private enum Field: Hashable {
        case keyword
        case details
    }

    enum Mode {
        case create
        case edit(Memory)

        var memory: Memory? {
            if case .edit(let memory) = self { memory } else { nil }
        }
    }

    let mode: Mode
    let repository: MemoryRepository
    /// Opens on the camera, for the Scan control: the value is scanned, the keyword typed.
    var startsScanning = false

    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String
    @State private var value: String
    @State private var lifetime: MemoryLifetime.Option
    @State private var untilDate: Date
    @State private var isSensitive: Bool
    @State private var saveError: String?
    @State private var hasVisitedDetails = false
    @State private var isScanning = false
    @FocusState private var focusedField: Field?

    init(mode: Mode, repository: MemoryRepository, startsScanning: Bool = false) {
        self.mode = mode
        self.repository = repository
        self.startsScanning = startsScanning
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

    private var showsKeywordHint: Bool {
        let keyword = MemoryNormalizer.normalizeKeyword(keyword)
        return hasVisitedDetails && !keyword.isEmpty && keyword.count < MemoryNormalizer.minimumKeywordLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Keyword", text: $keyword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .keyword)
                        if showsKeywordHint {
                            Text("Use a keyword with at least 4 characters so Spotlight can find it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    TextField("Value", text: $value, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .details)
                    fillButtons
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
                if startsScanning, ValueScanner.isSupported {
                    isScanning = true
                } else if case .create = mode {
                    focusedField = .keyword
                }
            }
            // Scanned or not, the keyword comes next.
            .sheet(isPresented: $isScanning, onDismiss: { if keyword.isEmpty { focusedField = .keyword } }) {
                ValueScanner { fill($0) }
            }
            .onChange(of: focusedField) { _, field in
                if field == .details, !MemoryNormalizer.normalizeKeyword(keyword).isEmpty {
                    hasVisitedDetails = true
                }
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

    /// Scan and Paste fill the value only. Paste is the system's button, which reads the
    /// clipboard without asking "Allow Paste?".
    private var fillButtons: some View {
        HStack(spacing: 10) {
            if ValueScanner.isSupported {
                Button { isScanning = true } label: {
                    Label("Scan", image: "ix.scan.linear")
                        // The accent is black, white in dark mode: the label takes the opposite.
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            PasteButton(payloadType: String.self) { @Sendable strings in
                guard let text = strings.first else { return }
                Task { @MainActor in fill(text) }
            }
            .labelStyle(.titleAndIcon)
        }
        // Prominent, as the system draws Paste, so the two match.
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    /// Takes a scanned or pasted value, then asks for the keyword if there is none yet:
    /// the keyword is always typed, since it is what the user will search for.
    private func fill(_ text: String) {
        let text = MemoryNormalizer.normalizeValue(text)
        guard !text.isEmpty else { return }
        value = text
        if !isScanning, keyword.isEmpty { focusedField = .keyword }
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
        guard canSave else { return }
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
