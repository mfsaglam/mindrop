#if os(iOS) || os(macOS)
import MindropCore
import SwiftUI

/// What the share sheet handed over.
public struct SharedContent: Sendable {
    public var text: String?
    public var image: Data?

    public init(text: String? = nil, image: Data? = nil) {
        self.text = text
        self.image = image
    }
}

/// Save-only form: the shared text arrives as the value, the user adds a keyword.
/// A shared image is read on the device and its lines offered to pick from.
///
/// Used by both share extensions and the iOS action extension.
@available(macOS 26.0, *)
public struct SaveToMindropView: View {
    private enum Field: Hashable {
        case keyword
        case details
    }

    let loadShared: () async -> SharedContent
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var keyword = ""
    @State private var value = ""
    @State private var lifetime = MemoryLifetime.Option.forever
    @State private var untilDate = Date.now.addingTimeInterval(7 * 24 * 60 * 60)
    @State private var isSensitive = false
    @State private var isSaving = false
    @State private var showsSaveError = false
    @State private var hasVisitedDetails = false
    #if os(iOS)
    @State private var imageLines = ImageLinesState.none
    #endif
    @FocusState private var focusedField: Field?

    public init(
        loadShared: @escaping () async -> SharedContent,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.loadShared = loadShared
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    private var canSave: Bool {
        !isSaving && (try? MemoryNormalizer.validate(keyword: keyword, value: value)) != nil
    }

    private var showsKeywordHint: Bool {
        let keyword = MemoryNormalizer.normalizeKeyword(keyword)
        return hasVisitedDetails && !keyword.isEmpty && keyword.count < MemoryNormalizer.minimumKeywordLength
    }

    public var body: some View {
        platformContent
            .alert(localized("Couldn’t save"), isPresented: $showsSaveError) {
                Button {} label: { localized("OK") }
            } message: {
                localized("Please try again.")
            }
            .onChange(of: focusedField) { _, field in
                if field == .details, !MemoryNormalizer.normalizeKeyword(keyword).isEmpty {
                    hasVisitedDetails = true
                }
            }
            .task { await load() }
    }

    private var platformContent: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            localized("Save to Mindrop")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], 16)

            form.formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button(role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                saveButton
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440, height: 455)
        #else
        NavigationStack {
            form
                .navigationTitle(localized("Save to Mindrop"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel, action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        saveButton
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                TextField(text: $keyword) { localized("Keyword") }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .keyword)
            } footer: {
                if showsKeywordHint {
                    localized("Use a keyword with at least 4 characters so Spotlight can find it.")
                } else {
                    localized("What you’ll type in Spotlight to find it.")
                }
            }
            Section {
                TextField(text: $value, axis: .vertical) { localized("Value") }
                    #if os(macOS)
                    .lineLimit(2...5)
                    #else
                    .lineLimit(2...)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .details)
            }
            #if os(iOS)
            ImageLinesSection(state: imageLines, value: $value)
            #endif
            MemoryOptionsSection(
                keyword: keyword,
                value: value,
                isSensitive: $isSensitive,
                option: $lifetime,
                date: $untilDate
            )
        }
    }

    private var saveButton: some View {
        Button(role: .confirm) { Task { await save() } }
            .disabled(!canSave)
    }

    private func load() async {
        #if os(macOS)
        focusedField = .keyword
        #endif
        let shared = await loadShared()
        if let text = shared.text, value.isEmpty { value = text }
        #if os(iOS)
        if let image = shared.image {
            imageLines = .reading
            imageLines = .read(await ImageTextReader.lines(in: image))
        }
        #endif
    }

    /// Strings in a package resolve against `Bundle.main`, which inside an extension
    /// is the extension's own bundle, so the catalog has to be named explicitly.
    private func localized(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module)
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        do {
            let expiresAt = MemoryLifetime(lifetime, until: untilDate).expiry(from: .now)
            #if os(macOS)
            try MacShareInbox.save(Memory.make(
                keyword: keyword, value: value, now: .now, expiresAt: expiresAt, isSensitive: isSensitive
            ))
            #else
            let repository = try MemoryRepository.live()
            try repository.load()
            try await repository.createAwaitingIndex(
                keyword: keyword,
                value: value,
                expiresAt: expiresAt,
                isSensitive: isSensitive
            )
            #endif
            onFinish()
        } catch {
            showsSaveError = true
            isSaving = false
        }
    }
}
#endif
