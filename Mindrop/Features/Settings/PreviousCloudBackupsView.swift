import CloudKit
import MindropCore
import SwiftUI

struct PreviousCloudBackupsView: View {
    private enum Action {
        case restore(MemoryBackup)
        case delete([MemoryBackup])
    }

    private struct Message: Identifiable {
        var id: String { detail }
        let title: LocalizedStringKey
        let detail: String
    }

    let repository: MemoryRepository
    let cloud: SavedCloudBackups

    @State private var isWorking = false
    @State private var confirmation: Action?
    @State private var message: Message?

    var body: some View {
        MemorySheetForm {
            Section {
                if isWorking || (cloud.backups == nil && cloud.isRefreshing) {
                    ProgressView()
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                }
                if let backups = cloud.backups {
                    if backups.isEmpty {
                        Text("No backups yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(backups) { backup in
                        backupRow(backup)
                            .disabled(isWorking)
                    }
                } else if !isWorking && !cloud.isRefreshing {
                    Button("Try Again") { Task { await load() } }
                }
            }

            if let backups = cloud.backups, backups.count > 1 {
                Section {
                    Button("Delete All Previous Backups", role: .destructive) { confirmation = .delete(backups) }
                        .disabled(isWorking)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("Previous iCloud Backups")
        .inlineNavigationTitle()
        .refreshable { await load() }
        .confirmationDialog(
            "Previous iCloud Backups",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .hidden,
            presenting: confirmation
        ) { action in
            switch action {
            case .restore(let backup):
                Button("Restore as Copies") { Task { await restore(backup) } }
            case .delete(let backups):
                Button(role: .destructive) {
                    Task { await delete(backups) }
                } label: {
                    backups.count == 1 ? Text("Delete Backup") : Text("Delete All Previous Backups")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            switch action {
            case .restore:
                Text("Adds copies of missing or changed memories that are still active.")
            case .delete(let backups):
                if backups.count == 1 {
                    Text("This backup will be deleted from iCloud on all your devices.")
                } else {
                    Text("The selected backups will be permanently deleted from iCloud on all your devices.")
                }
            }
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("OK")))
        }
    }

    private func backupRow(_ backup: MemoryBackup) -> some View {
        HStack {
            #if os(macOS)
            backupSummary(backup)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Restore Backup") { confirmation = .restore(backup) }
            Button(role: .destructive) { confirmation = .delete([backup]) } label: {
                Label("Delete Backup", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Delete Backup")
            #else
            Button {
                confirmation = .restore(backup)
            } label: {
                backupSummary(backup)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Restore Backup") { confirmation = .restore(backup) }
                Button("Delete Backup", role: .destructive) { confirmation = .delete([backup]) }
            } label: {
                Label("Backup Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #endif
    }

    private func backupSummary(_ backup: MemoryBackup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
            Text("Memories: \(backup.memoryCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        await perform("Couldn’t Load Backups") {
            try await cloud.refresh()
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

    private func delete(_ backups: [MemoryBackup]) async {
        await perform("Couldn’t Delete Backup") {
            try await cloud.delete(backups)
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
