import AppIntents
import Foundation
import MindropCore

/// Saves a memory without opening Mindrop: the Shortcuts action, for automations and for
/// text handed on from other actions.
///
/// The keyword is the shortcut's to give, typed by whoever made it or asked for when it
/// runs; Mindrop never makes one up. In the app target rather than `MindropIntents`, since
/// it needs the store, and runs in the app's process in the background.
struct SaveMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Mindrop"
    static let description = IntentDescription(
        "Save a memory without opening Mindrop. Find it later in Spotlight by keyword."
    )

    /// Posted once a memory is saved, for the app to pick it up if it is running.
    static let didSave = Notification.Name("SaveMemoryIntent.didSave")

    /// Typed as it will be searched, like the editor's field: no capital, no correction.
    @Parameter(
        title: "Keyword",
        inputOptions: String.IntentInputOptions(capitalizationType: .none, autocorrect: false),
        requestValueDialog: "What will you type in Spotlight to find it?"
    )
    var keyword: String

    @Parameter(
        title: "Value",
        inputOptions: String.IntentInputOptions(multiline: true),
        requestValueDialog: "What should Mindrop remember?"
    )
    var details: String

    @Parameter(title: "Keep", default: .forever)
    var keep: KeepOption

    @Parameter(title: "Sensitive", default: false)
    var isSensitive: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$details) as \(\.$keyword)") {
            \.$keep
            \.$isSensitive
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try MemoryNormalizer.validate(keyword: keyword, value: details)
        } catch let error as MemoryValidationError {
            throw SaveMemoryError(error)
        }

        let repository = try MemoryRepository.live(spotlightExtras: MindropSession.spotlightExtras)
        try repository.load()
        // Waits for Spotlight, as the share extension does: launched in the background
        // just for this, the app may be suspended as soon as the action returns.
        let memory = try await repository.createAwaitingIndex(
            keyword: keyword,
            value: details,
            expiresAt: keep.lifetime.expiry(from: .now),
            isSensitive: isSensitive
        )
        NotificationCenter.default.post(name: Self.didSave, object: nil)
        return .result(dialog: "Saved. Type “\(memory.keyword)” in Spotlight to find it.")
    }
}

/// How long to keep the memory: the editor's choices, less a date of its own, which a
/// shortcut can't usefully fix in advance.
enum KeepOption: String, AppEnum {
    case forever
    case day
    case week
    case month

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Keep"
    static let caseDisplayRepresentations: [KeepOption: DisplayRepresentation] = [
        .forever: "Forever",
        .day: "1 Day",
        .week: "1 Week",
        .month: "1 Month",
    ]

    var lifetime: MemoryLifetime {
        switch self {
        case .forever: .forever
        case .day: .day
        case .week: .week
        case .month: .month
        }
    }
}

/// Why a memory couldn't be saved, worded for Shortcuts' alert.
struct SaveMemoryError: Error, CustomLocalizedStringResourceConvertible {
    let reason: MemoryValidationError

    init(_ reason: MemoryValidationError) {
        self.reason = reason
    }

    var localizedStringResource: LocalizedStringResource {
        switch reason {
        case .emptyKeyword: "Add a keyword to type in Spotlight."
        case .keywordTooShort: "Use a keyword with at least 4 characters so Spotlight can find it."
        case .emptyValue: "Add the details to remember."
        }
    }
}
