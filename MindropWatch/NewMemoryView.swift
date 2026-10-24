import SwiftUI
import WatchKit

/// The whole watch app: a keyword, a value, whether it is sensitive, and Save. The iPhone
/// does the rest — files it, adds it to Spotlight, picks a category.
struct NewMemoryView: View {
    @ObservedObject var sender: WatchSender

    @State private var keyword = ""
    @State private var value = ""
    @State private var isSensitive = false
    @State private var showsSaved = false
    @Environment(\.scenePhase) private var scenePhase

    private var canSave: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Keyword", text: $keyword)
                    TextField("Value", text: $value)
                }

                Section {
                    Toggle("Sensitive", isOn: $isSensitive)
                }

                Section {
                    Button(action: save) {
                        Label("Save", image: "ix.add.linear")
                            .labelStyle(.titleAndIcon)
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                    }
                    .modifier(SaveButtonStyle())
                    .disabled(!canSave)
                    .listRowBackground(Color.clear)
                } footer: {
                    status
                }
            }
            .navigationTitle(Text(verbatim: "Mindrop"))
        }
        .overlay {
            if showsSaved {
                savedConfirmation
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { sender.send() }
        }
    }

    @ViewBuilder
    private var status: some View {
        if sender.waitingCount > 0 {
            Text("Waiting to reach your iPhone: \(sender.waitingCount)")
        } else {
            Text("Your iPhone takes it from here and adds it to Spotlight.")
        }
    }

    private var savedConfirmation: some View {
        VStack(spacing: 8) {
            Image("ix.tick-circle.linear")
                .font(.system(size: 44))
            Text("Saved")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard sender.save(keyword: keyword, value: value, isSensitive: isSensitive) else { return }
        keyword = ""
        value = ""
        isSensitive = false
        WKInterfaceDevice.current().play(.success)
        withAnimation(.easeOut(duration: 0.2)) { showsSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeIn(duration: 0.2)) { showsSaved = false }
        }
    }
}

/// Liquid Glass from watchOS 26; the standard filled button on older watches.
private struct SaveButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}
