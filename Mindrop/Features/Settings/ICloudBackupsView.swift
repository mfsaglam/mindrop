import CloudKit
import MindropCore
import SwiftUI

struct ICloudBackupsView: View {
    private enum Action {
        case restore(MemoryBackup)
        case delete(MemoryBackup)
    }

    private struct Message: Identifiable {
        var id: String { detail }
        let title: LocalizedStringKey
        let detail: String
    }

    let repository: MemoryRepository
    let drive: DriveMemoryBackup
    private let cloud = CloudMemoryBackup()

    @State private var backups: [MemoryBackup] = []
    @State private var isWorking = false
    @State private var hasLoaded = false
    @State private var confirmation: Action?
    @State private var message: Message?

    var body: some View {
        Form {
            Section {
                NavigationLink("iCloud Drive Backups") {
                    DriveBackupsView(repository: repository, drive: drive)
                }
            }

            Section {
                Button("Back Up Now") { Task { await create() } }
                    .disabled(isWorking)
            } footer: {
                Text("A backup keeps a dated copy of your active memories in iCloud. Backups stay available until you delete them.")
            }

            Section("Saved Backups") {
                if isWorking {
                    ProgressView()
                }
                if backups.isEmpty, hasLoaded {
                    Text("No backups yet.")
                        .foregroundStyle(.secondary)
                }
                if !hasLoaded, !isWorking {
                    Button("Try Again") { Task { await load() } }
                }
                ForEach(backups) { backup in
                    HStack {
                        Button {
                            confirmation = .restore(backup)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Text("Memories: \(backup.memoryCount)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Restore Backup") { confirmation = .restore(backup) }
                            Button("Delete Backup", role: .destructive) { confirmation = .delete(backup) }
                        } label: {
                            Label("Backup Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle("iCloud Backup")
        .inlineNavigationTitle()
        .task { await load() }
        .confirmationDialog(
            "iCloud Backup",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .hidden,
            presenting: confirmation
        ) { action in
            switch action {
            case .restore(let backup):
                Button("Restore as Copies") { Task { await restore(backup) } }
            case .delete(let backup):
                Button("Delete Backup", role: .destructive) { Task { await delete(backup) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            switch action {
            case .restore:
                Text("Adds copies of missing or changed memories that are still active.")
            case .delete:
                Text("This backup will be deleted from iCloud on all your devices.")
            }
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("OK")))
        }
    }

    private func load() async {
        await perform("Couldn’t Load Backups") {
            backups = try await cloud.list()
            hasLoaded = true
        }
    }

    private func create() async {
        await perform("Couldn’t Create Backup") {
            let memories = try repository.memoriesForBackup()
            guard !memories.isEmpty else {
                message = Message(title: "No Memories to Back Up", detail: String(localized: "Save a memory before creating a backup."))
                return
            }
            let backup = try await cloud.create(memories: memories)
            backups.insert(backup, at: 0)
        }
    }

    private func restore(_ backup: MemoryBackup) async {
        await perform("Couldn’t Restore Backup") {
            let memories = try await cloud.memories(in: backup)
            let count = try repository.restore(memories, from: backup)
            let detail = count == 0
                ? String(localized: "This backup has no additional memories to restore.")
                : String(localized: "Memories restored: \(count)")
            message = Message(title: "Restore Complete", detail: detail)
        }
    }

    private func delete(_ backup: MemoryBackup) async {
        await perform("Couldn’t Delete Backup") {
            try await cloud.delete(backup)
            backups.removeAll { $0.id == backup.id }
        }
    }

    private func perform(_ errorTitle: LocalizedStringKey, operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            let detail = (error as? CKError)?.code == .notAuthenticated
                ? String(localized: "Sign in to iCloud on this device and try again.")
                : error.localizedDescription
            message = Message(title: errorTitle, detail: detail)
        }
    }
}
