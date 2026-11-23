#if os(iOS)
import Foundation
import MindropCore
import MindropWidgetData
import OSLog
import WidgetKit

extension StackWidgetSnapshot.Record {
    init(memory: Memory) {
        self.init(
            keyword: String(memory.keyword.prefix(128)),
            value: String(memory.value.prefix(256)),
            expiresAt: memory.expiresAt
        )
    }
}

@MainActor
final class StackWidgetPublisher {
    private let logger = Logger(subsystem: "mfsaglam.Mindrop", category: "stack-widget")
    private var lastPublished: StackWidgetSnapshot?

    func publish(_ memories: [Memory]) {
        guard let url = StackWidgetSnapshot.fileURL else { return }
        let snapshot = StackWidgetSnapshot(records: memories.map(StackWidgetSnapshot.Record.init(memory:)))
        if lastPublished == nil { lastPublished = StackWidgetSnapshot.read(from: url) }
        guard snapshot != lastPublished else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastPublished = snapshot
        } catch {
            logger.error("Could not publish the Stack snapshot: \(error.localizedDescription, privacy: .private)")
            // A stale file may now contain a removed or newly sensitive record.
            try? FileManager.default.removeItem(at: url)
            lastPublished = nil
        }
        WidgetCenter.shared.reloadTimelines(ofKind: StackWidgetSnapshot.lockScreenKind)
        WidgetCenter.shared.reloadTimelines(ofKind: StackWidgetSnapshot.homeScreenKind)
    }
}
#endif
