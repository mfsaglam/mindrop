import MindropCore
import SwiftUI
import WatchConnectivity

/// Settings → How Mindrop Works: the empty list's guide again, for anyone who has saved
/// since, then the ways to save without opening Mindrop first. Nothing in the app leads to
/// those, so this is where they are told.
struct HowMindropWorksView: View {
    /// Taken once: the guide's animation steps through examples made from these, so they
    /// must not change under it while iCloud sync or the watch adds a memory.
    @State private var memories: [Memory]

    init(repository: MemoryRepository) {
        _memories = State(initialValue: repository.results(for: ""))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 44) {
                SpotlightGuide(memories: memories)
                MoreWaysToSave()
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .navigationTitle("How Mindrop Works")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The other ways in, each with where to find it. Those that point at Apple's own features
/// carry Apple's symbols, the ones people know from those features; Scan is Mindrop's own,
/// so it carries the icon its button has.
private struct MoreWaysToSave: View {
    /// Only for someone with a watch: to anyone else it is a feature they can't use.
    private var hasPairedWatch: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isPaired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("More Ways to Save")
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity)

            // Only where the editor offers Scan.
            if ValueScanner.isSupported {
                way(Image("ix.scan.linear"), Text("Scan"),
                    Text("In a new memory, tap +, then Scan. Point the camera at text or a QR code and tap what to save."))
            }
            way(Image("ix.gallery.linear"), Text("From a Photo"),
                Text("In a new memory, tap +, then Choose Photo, and tap the lines you want."))
            way("square.and.arrow.up", Text("From Other Apps"),
                Text("Tap Share and choose Mindrop to save text, a link or a screenshot. If it isn’t there, tap More."))
            way("switch.2", Text("Control Center"),
                Text("Open Control Center, tap +, then Add a Control, and choose Mindrop. It can go on the Lock Screen too."))
            way("button.programmable", Text("Action Button"),
                Text("If your iPhone has one, go to Settings › Action Button, choose Shortcut, then Mindrop."))
            way("siri", Text(verbatim: "Siri"),
                Text("Say “New memory in Mindrop”, or “Scan into Mindrop” to start with the camera."))
            if hasPairedWatch {
                way("applewatch", Text(verbatim: "Apple Watch"),
                    Text("Open Mindrop on your Apple Watch to save a memory from your wrist."))
            }
        }
        .padding(.horizontal, 8)
    }

    private func way(_ symbol: String, _ title: Text, _ detail: Text) -> some View {
        way(Image(systemName: symbol), title, detail)
    }

    private func way(_ icon: Image, _ title: Text, _ detail: Text) -> some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.body.weight(.semibold))
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
