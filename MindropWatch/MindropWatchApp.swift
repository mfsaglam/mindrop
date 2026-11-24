import MindropWidgetData
import SwiftUI

@main
struct MindropWatchApp: App {
    @StateObject private var sender = WatchSender()
    @State private var showsStack = false

    var body: some Scene {
        WindowGroup {
            NewMemoryView(sender: sender)
                .onOpenURL { url in
                    if url == StackWidgetSnapshot.stackURL { showsStack = true }
                }
                .sheet(isPresented: $showsStack) {
                    WatchStackView(sender: sender)
                }
        }
        .backgroundTask(.watchConnectivity) {
            await sender.receiveBackgroundUpdates()
        }
    }
}
