import Foundation
import MindropCore
import WatchConnectivity

/// The iPhone's end of the Apple Watch link. Memories saved on the watch arrive here as
/// user-info transfers and are taken in like memories synced from another device: filed,
/// added to Spotlight, categorised, then sent to iCloud. The watch is told whether iCloud
/// Sync is on, so it writes to iCloud itself only when the user lets Mindrop use it.
///
/// Activated as the app starts, before the library is loaded: the system may launch the app
/// in the background just to hand it a transfer.
@MainActor
final class WatchLink: NSObject {
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    /// Takes in a memory from the watch. Set once the library is loaded; until then,
    /// arrivals wait in `arrivals`.
    private var receive: ((Memory) -> Void)?
    private var arrivals: [Memory] = []
    private var syncsWithICloud: Bool

    init(syncsWithICloud: Bool) {
        self.syncsWithICloud = syncsWithICloud
        super.init()
        session?.delegate = self
        session?.activate()
        #if DEBUG
        // `-debugWatchArrival "keyword=value"`: a memory as if it had just come from the
        // watch, for testing what happens to it here without a paired watch.
        if let pair = UserDefaults.standard.string(forKey: "debugWatchArrival"),
           let separator = pair.firstIndex(of: "="),
           let memory = WatchHandoff.newMemory(
               keyword: String(pair[..<separator]),
               value: String(pair[pair.index(after: separator)...]),
               isSensitive: false
           ),
           let userInfo = try? WatchHandoff.userInfo(for: memory) {
            self.session(.default, didReceiveUserInfo: userInfo)
        }
        #endif
    }

    /// Starts handing memories from the watch to `receive`, beginning with any that arrived
    /// while the library was loading.
    func deliver(to receive: @escaping (Memory) -> Void) {
        self.receive = receive
        let waiting = arrivals
        arrivals = []
        waiting.forEach(receive)
    }

    /// Follows the Settings switch.
    func setSyncsWithICloud(_ on: Bool) {
        syncsWithICloud = on
        sendContext()
    }

    private func sendContext() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(WatchHandoff.applicationContext(syncsWithICloud: syncsWithICloud))
    }

    private func arrived(_ memory: Memory) {
        if let receive {
            receive(memory)
        } else {
            arrivals.append(memory)
        }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let memory = WatchHandoff.memory(from: userInfo) else { return }
        Task { @MainActor in self.arrived(memory) }
    }

    /// The watch app was installed or removed, or another watch was paired.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendContext() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: the new one needs a session of its own.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
