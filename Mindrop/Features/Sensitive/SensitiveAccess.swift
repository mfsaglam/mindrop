import LocalAuthentication
import MindropCore
import Observation
import SwiftUI

/// Whether sensitive values may be shown. One unlock shows them all until the app goes
/// to the background, the way locked notes stay open while you work with them.
@MainActor
@Observable
final class SensitiveAccess {
    private(set) var isUnlocked = false

    func canShow(_ memory: Memory) -> Bool {
        !memory.isSensitive || isUnlocked
    }

    /// Asks for Face ID, Touch ID or the passcode. True if the value may be shown now.
    ///
    /// Without a passcode the iPhone itself is open to anyone, and iOS has nothing to
    /// ask for, so the value is shown.
    @discardableResult
    func unlock() async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if (error as? LAError)?.code == .passcodeNotSet {
                isUnlocked = true
            }
            return isUnlocked
        }
        do {
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Show your sensitive memories")
            )
        } catch {
            // Cancelled or failed: the value stays hidden, and the user can try again.
        }
        return isUnlocked
    }

    func lock() {
        isUnlocked = false
    }
}

extension EnvironmentValues {
    @Entry var sensitiveAccess = SensitiveAccess()
}

/// Stands in for a sensitive value while it is hidden. As many dots for every value, so
/// they give nothing away about its length.
struct HiddenValue: View {
    var body: some View {
        Text(verbatim: "••••••••")
            .accessibilityLabel(Text("Hidden"))
    }
}

/// Marks a sensitive memory next to its keyword, hidden or not.
struct SensitiveBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Sensitive"))
    }
}
