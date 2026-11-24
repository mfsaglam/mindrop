import MindropCore
import MindropSaveUI
import PhotosUI
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
    private let folderID: UUID
    private let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyword: String
    @State private var value: String
    @State private var lifetime: MemoryLifetime.Option
    @State private var untilDate: Date
    @State private var isSensitive: Bool
    @State private var addsToStack = false
    @State private var saveError: String?
    @State private var hasVisitedDetails = false
    @State private var keywordWarningID: UUID?
    @State private var highlightsKeywordWarning = false
    @State private var valueWarningID: UUID?
    @State private var showsValueWarning = false
    #if os(iOS)
    @State private var isScanning = false
    #endif
    @State private var isChoosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var imageLines = ImageLinesState.none
    @FocusState private var focusedField: Field?

    init(
        mode: Mode, repository: MemoryRepository, startsScanning: Bool = false,
        initialDetails: String = "", folderID: UUID = MemoryFolders.generalID, onClose: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.repository = repository
        self.startsScanning = startsScanning
        self.folderID = folderID
        self.onClose = onClose
        switch mode {
        case .create:
            _keyword = State(initialValue: "")
            _value = State(initialValue: initialDetails)
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

    private var normalizedKeyword: String { MemoryNormalizer.normalizeKeyword(keyword) }
    private var isKeywordTooShort: Bool { normalizedKeyword.count < MemoryNormalizer.minimumKeywordLength }
    private var isValueEmpty: Bool { MemoryNormalizer.normalizeValue(value).isEmpty }

    var body: some View {
        editor
            // A new memory starts with the keyboard up, so the control and the Action
            // button land the user straight in typing.
            .onAppear {
                #if os(macOS)
                if case .create = mode {
                    // AppKit may load the hosting view before it makes the window key.
                    DispatchQueue.main.async { focusedField = .keyword }
                }
                #else
                if startsScanning, ValueScanner.isSupported {
                    isScanning = true
                    return
                }
                if case .create = mode { focusedField = .keyword }
                #endif
            }
            #if os(iOS)
            // Scanned or not, the keyword comes next.
            .sheet(isPresented: $isScanning, onDismiss: { if keyword.isEmpty { focusedField = .keyword } }) {
                ValueScanner { fill($0) }
            }
            #endif
            .photosPicker(isPresented: $isChoosingPhoto, selection: $photo, matching: .images)
            .task(id: photo) {
                guard let photo else { return }
                imageLines = .reading
                if let data = try? await photo.loadTransferable(type: Data.self) {
                    imageLines = .read(await ImageTextReader.lines(in: data))
                } else {
                    imageLines = .read([])
                }
            }
            .onChange(of: focusedField) { _, field in
                if field == .details, !normalizedKeyword.isEmpty {
                    hasVisitedDetails = true
                }
            }
            .onChange(of: isKeywordTooShort) { _, isShort in
                if !isShort { highlightsKeywordWarning = false }
            }
            .onChange(of: isValueEmpty) { _, isEmpty in
                if !isEmpty { showsValueWarning = false }
            }
            .task(id: keywordWarningID) {
                guard let warningID = keywordWarningID else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, keywordWarningID == warningID else { return }
                highlightsKeywordWarning = false
            }
            .onChange(of: isSensitive) { _, sensitive in
                if sensitive { addsToStack = false }
            }
            .alert("Couldn’t save", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text("Please try again.")
            }
    }

    private var keywordHint: some View {
        let showsLengthHint = isKeywordTooShort && (highlightsKeywordWarning || (hasVisitedDetails && !normalizedKeyword.isEmpty))
        let message: LocalizedStringKey = showsLengthHint
            ? "Use a keyword with at least 4 characters so Spotlight can find it."
            : "What you’ll type in Spotlight to find it."
        return Text(message)
            .foregroundStyle(showsLengthHint && highlightsKeywordWarning ? Color.pink : Color.secondary)
            .shakeOnInvalidSave(trigger: keywordWarningID, reduceMotion: reduceMotion)
    }

    private func valueWarningOutline(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(showsValueWarning ? Color.pink : Color.clear, lineWidth: 2)
            .allowsHitTesting(false)
    }

    private var memoryOptions: some View {
        MemoryOptionsSection(
            keyword: keyword,
            value: value,
            isSensitive: $isSensitive,
            option: $lifetime,
            date: $untilDate,
            earliestDate: mode.memory?.expiresAt.map { min($0, .now) } ?? .now,
            sensitiveToggleTint: Color(.brandCobalt)
        )
    }

    private var stackOption: some View {
        Toggle("Show in Stack", isOn: $addsToStack)
            .tint(Color(.brandCobalt))
            .disabled(isSensitive)
    }

    #if os(macOS)
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keyword").fontWeight(.medium)
                        TextField("Keyword", text: $keyword, prompt: Text(verbatim: ""))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .keyword)
                            .onSubmit { focusedField = .details }
                        keywordHint
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Value").fontWeight(.medium)
                        TextEditor(text: $value)
                            .accessibilityLabel(Text("Value"))
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .details)
                            .font(.body)
                            .padding(6)
                            .frame(minHeight: 116)
                            .background(.background, in: .rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)
                            }
                            .overlay { valueWarningOutline(cornerRadius: 8) }
                            .shakeOnInvalidSave(trigger: valueWarningID, reduceMotion: reduceMotion)
                            .accessibilityHint(showsValueWarning ? Text("Add the details to remember.") : Text(verbatim: ""))
                        Button("Choose Photo", systemImage: "photo") {
                            isChoosingPhoto = true
                        }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    ImageLinesSection(state: imageLines, value: $value)
                    memoryOptions
                    if case .create = mode { stackOption }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .defaultFocus($focusedField, .keyword)
        .frame(width: 500, height: 510)
    }
    #else
    private var editor: some View {
        NavigationStack {
            MemorySheetForm {
                Section {
                    TextField("Keyword", text: $keyword)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .keyword)
                        .onSubmit { focusedField = .details }
                } footer: {
                    keywordHint
                }
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        TextField("Value", text: $value, axis: .vertical)
                            .lineLimit(2...)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .details)
                            .accessibilityHint(showsValueWarning ? Text("Add the details to remember.") : Text(verbatim: ""))
                        detailsSources
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay { valueWarningOutline(cornerRadius: 24) }
                    .shakeOnInvalidSave(trigger: valueWarningID, reduceMotion: reduceMotion)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    // The system's Paste button: it reads the clipboard without asking
                    // "Allow Paste?", which a button in a menu could not.
                    HStack {
                        Spacer()
                        PasteButton(payloadType: String.self) { @Sendable strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in fill(text) }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                }
                ImageLinesSection(state: imageLines, value: $value)
                memoryOptions
                if case .create = mode {
                    Section { stackOption }
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                }
            }
        }
    }
    #endif

    /// One + beside the details, for filling them other than by typing: Scan, where the
    /// iPhone can, and a photo, whose lines are then offered as pills.
    #if os(iOS)
    private var detailsSources: some View {
        Menu {
            #if os(iOS)
            if ValueScanner.isSupported {
                Button { isScanning = true } label: {
                    Label("Scan", systemImage: "text.viewfinder")
                }
            }
            #endif
            Button {
                // The keyboard stays down after the picker, so the lines can be seen and picked.
                focusedField = nil
                isChoosingPhoto = true
            } label: {
                Label("Choose Photo", systemImage: "photo")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("Fill In Details"))
    }

    #endif

    /// Takes a scanned or pasted value, then asks for the keyword if there is none yet:
    /// the keyword is always typed, since it is what the user will search for.
    private func fill(_ text: String) {
        let text = MemoryNormalizer.normalizeValue(text)
        guard !text.isEmpty else { return }
        value = text
        #if os(iOS)
        guard !isScanning else { return }
        #endif
        if keyword.isEmpty { focusedField = .keyword }
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
        let needsKeyword = isKeywordTooShort
        let needsValue = isValueEmpty
        if needsKeyword || needsValue {
            if needsKeyword {
                hasVisitedDetails = true
                highlightsKeywordWarning = true
                keywordWarningID = UUID()
            }
            if needsValue {
                showsValueWarning = true
                valueWarningID = UUID()
            }
            focusedField = needsKeyword ? .keyword : .details
            return
        }

        do {
            let expiresAt = MemoryLifetime(lifetime, until: untilDate).expiry(from: .now)
            switch mode {
            case .create:
                try repository.create(
                    keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive,
                    folderID: folderID, addsToStack: addsToStack
                )
            case .edit(let memory):
                try repository.update(
                    memory,
                    keyword: keyword,
                    value: value,
                    expiresAt: expiresAt,
                    isSensitive: isSensitive
                )
            }
            close()
        } catch {
            saveError = String(describing: error)
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

private extension View {
    func shakeOnInvalidSave(trigger: UUID?, reduceMotion: Bool) -> some View {
        keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, offset in
            content.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            CubicKeyframe(-5, duration: 0.06)
            CubicKeyframe(5, duration: 0.08)
            CubicKeyframe(-3, duration: 0.08)
            CubicKeyframe(2, duration: 0.07)
            CubicKeyframe(0, duration: 0.07)
        }
    }
}
