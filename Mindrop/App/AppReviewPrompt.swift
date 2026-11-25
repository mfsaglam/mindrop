import Foundation

@MainActor
enum AppReviewPrompt {
    static let presentationDelay: Duration = .seconds(2)

    private static let requiredCreations = 5
    private static let minimumRequestInterval: TimeInterval = 120 * 24 * 60 * 60

    private enum Key {
        static let creations = "appReview.successfulCreations"
        static let lastRequestDate = "appReview.lastRequestDate"
        static let lastRequestVersion = "appReview.lastRequestVersion"
    }

    static func recordSuccessfulCreation() -> Bool {
        let defaults = UserDefaults.standard
        let creations = defaults.integer(forKey: Key.creations)
        if creations < requiredCreations {
            defaults.set(creations + 1, forKey: Key.creations)
        }
        return eligibleVersion(in: defaults, at: .now) != nil
    }

    static func requestIfEligible(_ requestReview: () -> Void) {
        let defaults = UserDefaults.standard
        let now = Date.now
        guard let version = eligibleVersion(in: defaults, at: now) else { return }

        // StoreKit doesn't report whether it showed the prompt or whether the person rated.
        defaults.set(now, forKey: Key.lastRequestDate)
        defaults.set(version, forKey: Key.lastRequestVersion)
        defaults.set(0, forKey: Key.creations)
        requestReview()
    }

    private static func eligibleVersion(in defaults: UserDefaults, at date: Date) -> String? {
        guard defaults.integer(forKey: Key.creations) >= requiredCreations,
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty, defaults.string(forKey: Key.lastRequestVersion) != version else { return nil }

        if let lastRequest = defaults.object(forKey: Key.lastRequestDate) as? Date,
           date.timeIntervalSince(lastRequest) < minimumRequestInterval { return nil }
        return version
    }
}
