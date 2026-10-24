#if os(iOS)
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
/// Shown by both extensions — the share sheet's app row and its action row — which
/// differ only in how iOS lists them, not in what the user does here.
public struct SaveToMindropView: View {
    private enum Field: Hashable {
        case keyword
        case details
    }

    private enum ImageReading {
        case none
        case reading
        case read([String])
    }

    /// Lines shown before Show All; a screenshot can hold dozens.
    private static let linesShownAtFirst = 8

    let loadShared: () async -> SharedContent
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
    @State private var imageReading = ImageReading.none
    @State private var showsAllLines = false
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
                imageSection
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
            let shared = await loadShared()
            if let text = shared.text, value.isEmpty {
                value = text
            }
            if let image = shared.image {
                imageReading = .reading
                imageReading = .read(await ImageTextReader.lines(in: image))
            }
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        switch imageReading {
        case .none:
            EmptyView()
        case .reading:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    localized("Reading the image…")
                }
                .foregroundStyle(.secondary)
            } header: {
                localized("From the Image")
            }
        case .read(let lines) where lines.isEmpty:
            Section {
                localized("No text found in the image.")
                    .foregroundStyle(.secondary)
            } header: {
                localized("From the Image")
            }
        case .read(let lines):
            Section {
                let shown = showsAllLines ? lines : Array(lines.prefix(Self.linesShownAtFirst))
                ForEach(shown, id: \.self) { line in
                    imageLine(line)
                }
                if shown.count < lines.count {
                    Button { showsAllLines = true } label: { localized("Show All") }
                }
            } header: {
                localized("From the Image")
            } footer: {
                localized("Tap the lines to put in the details.")
            }
        }
    }

    private func imageLine(_ line: String) -> some View {
        let isPicked = ImageText.details(value, contain: line)
        return Button {
            value = ImageText.toggling(line, in: value)
        } label: {
            HStack(spacing: 12) {
                Text(line)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(isPicked ? 1 : 0)
            }
        }
        .accessibilityAddTraits(isPicked ? .isSelected : [])
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
