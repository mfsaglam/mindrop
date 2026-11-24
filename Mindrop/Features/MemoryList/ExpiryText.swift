import MindropCore
import SwiftUI

/// "Expires tomorrow" for a temporary memory, "Deleted for good in 6 days" for an expired
/// one, nothing for a memory kept forever. Shared by the list and the detail screen.
struct ExpiryText: View {
    private let memory: Memory
    private let isExpired: Bool

    init?(memory: Memory, now: Date = .now) {
        guard memory.expiresAt != nil else { return nil }
        self.memory = memory
        isExpired = memory.isExpired(at: now)
    }

    var body: some View {
        HStack(spacing: 4) {
            if isExpired, let deletion = memory.deletionDate {
                Image(systemName: "trash")
                Text("Deleted for good \(deletion, format: .relative(presentation: .named))")
            } else if let expiry = memory.expiresAt {
                Image(systemName: "timer")
                Text("Expires \(expiry, format: .relative(presentation: .named))")
            }
        }
    }
}
