import SwiftUI

/// Mindrop on Apple Watch: saving a memory without reaching for the iPhone. Searching stays
/// on the iPhone, in Spotlight. Runs on watchOS 9 and later, the oldest Xcode 27 builds
/// for, so Series 4, Series 5 and the first SE work too.
@main
struct MindropWatchApp: App {
    @StateObject private var sender = WatchSender()

    var body: some Scene {
        WindowGroup {
            NewMemoryView(sender: sender)
        }
    }
}
