#if os(iOS)
import MindropCore
import SwiftUI

/// Save-only form: the shared text arrives as the value, the user adds a keyword.
///
/// Shown by both extensions — the share sheet's app row and its action row — which
/// differ only in how iOS lists them, not in what the user does here.
public struct SaveToMindropView: View {
    private enum Field: Hashable {
        case keyword
        case details
    }

    let loadSharedValue: () async -> String?
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var keyword = ""
    @State private var value = ""
    @State private var lifetime = MemoryLifetime.Option.forever
    @State private var untilDate = Date.now.addingTimeInterval(7 * 24 * 60 * 60)
    @State private var isSensitive = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hasVisitedDetails = false
    @FocusState private var focusedField: Field?

    public init(
        loadSharedValue: @escaping () async -> String?,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.loadSharedValue = loadSharedValue
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
        NavigationStack {
            Form {
                Section {
                    TextField(text: $keyword) { localized("Keyword") }
                        .textInputAutocapitalization(.never)
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
                        .lineLimit(2...)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .details)
                }
                MemoryOptionsSection(
                    keyword: keyword,
                    value: value,
                    isSensitive: $isSensitive,
                    option: $lifetime,
                    date: $untilDate
                )
            }
            .navigationTitle(localized("Save to Mindrop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .alert(localized("Couldn’t save"), isPresented: .constant(errorMessage != nil)) {
                Button { errorMessage = nil } label: { localized("OK") }
            } message: {
                localized("Please try again.")
            }
        }
        .onChange(of: focusedField) { _, field in
            if field == .details, !MemoryNormalizer.normalizeKeyword(keyword).isEmpty {
                hasVisitedDetails = true
            }
        }
        .task {
            if let shared = await loadSharedValue(), value.isEmpty {
                value = shared
            }
        }
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
            let repository = try MemoryRepository.live()
            try repository.load()
            let expiresAt = MemoryLifetime(lifetime, until: untilDate).expiry(from: .now)
            try await repository.createAwaitingIndex(
                keyword: keyword,
                value: value,
                expiresAt: expiresAt,
                isSensitive: isSensitive
            )
            onFinish()
        } catch {
            errorMessage = String(describing: error)
            isSaving = false
        }
    }
}
#endif
