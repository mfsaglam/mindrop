#if os(macOS)
import AppKit
import MindropCore

final class MacServices: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(importSharedMemories), name: MacShareInbox.didSave,
            object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func importSharedMemories(_ notification: Notification) {
        MindropSession.shared.importMacShares()
    }

    @objc(saveSelection:userData:error:)
    func saveSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let details = MemoryNormalizer.normalizeValue(pasteboard.string(forType: .string) ?? "")
        guard !details.isEmpty else {
            error.pointee = String(localized: "Select some text to save in Mindrop.") as NSString
            return
        }
        MindropSession.shared.showMacCapture(details: details)
    }
}
#endif
