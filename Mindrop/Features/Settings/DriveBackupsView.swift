import MindropCore
import SwiftUI
import UniformTypeIdentifiers

struct DriveBackupsView: View {
    private struct Restore {
        let backup: MemoryBackup
        let memories: [Memory]
    }

    let repository: MemoryRepository
    let drive: DriveMemoryBackup

    @AppStorage(Preference.automaticDriveBackup) private var automatic = false
    @State private var status: DriveMemoryBackup.Status?
    @State private var statusError: String?
    @State private var isWorking = false
    @State private var showsImporter = false
    @State private var pendingRestore: Restore?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Automatic Backups", isOn: $automatic)
                    .disabled(isWorking)
                    .onChange(of: automatic) { _, enabled in
                        if enabled { Task { await create(automatically: true) } }
                    }
                Button("Back Up Now") {
                    Task { await create(automatically: false) }
                }
                .disabled(isWorking)
                Button("Restore from File") { showsImporter = true }
                    .disabled(isWorking)
            } footer: {
                Text("Find encrypted backups in iCloud Drive → Mindrop → Backups. Keep iCloud Keychain on to restore on your other devices.")
            }

            Section {
                if let date = status?.lastUploadedAt {
                    LabeledContent {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    } label: {
                        Text("Last Successful Backup")
                    }
                } else {
                    Text("No confirmed upload on this device.")
                        .foregroundStyle(.secondary)
                }
                if isWorking || status?.uploadPending == true {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(isWorking ? "Preparing Backup or Restore…" : "Waiting for iCloud Drive to upload…")
                    }
                }
                if let error = status?.uploadError ?? statusError {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Mindrop checks for changes when you open the app and backs up at most once every 24 hours per device.")
            }
        }
        .navigationTitle("iCloud Drive Backups")
        .inlineNavigationTitle()
        .task {
            while !Task.isCancelled {
                await refresh()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.mindropBackup]) { result in
            Task { await prepareRestore(result) }
        }
        .confirmationDialog(
            "Restore Backup",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { restore in
            Button("Restore as Copies") { apply(restore) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Adds copies of missing or changed memories that are still active.")
        }
        .alert("iCloud Drive Backups", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func refresh() async {
        do {
            status = try await drive.status()
            statusError = nil
        } catch {
            status = nil
            statusError = automatic ? description(for: error) : nil
        }
    }

    private func create(automatically: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await drive.authorizeCurrentAccount()
            let memories = try repository.memoriesForBackup()
            if memories.isEmpty, !automatically {
                message = String(localized: "Save a memory before creating a backup.")
            } else {
                try await drive.create(memories: memories, automatically: automatically)
            }
        } catch {
            message = description(for: error)
        }
        await refresh()
    }

    private func prepareRestore(_ result: Result<URL, any Error>) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let (backup, memories) = try await drive.open(result.get())
            pendingRestore = Restore(backup: backup, memories: memories)
        } catch {
            message = description(for: error)
        }
    }

    private func apply(_ restore: Restore) {
        do {
            let count = try repository.restore(restore.memories, from: restore.backup)
            message = count == 0
                ? String(localized: "This backup has no additional memories to restore.")
                : String(localized: "Memories restored: \(count)")
        } catch {
            message = description(for: error)
        }
    }

    private func description(for error: any Error) -> String {
        switch error {
        case DriveBackupError.driveUnavailable:
            String(localized: "Turn on iCloud Drive on this device and try again.")
        case DriveBackupError.accountChanged:
            String(localized: "Confirm this iCloud account with Back Up Now, or turn automatic backups off and on.")
        case DriveBackupError.keyUnavailable, DriveBackupError.keychain:
            String(localized: "The backup key is unavailable. Check iCloud Keychain or use the device that created the backup.")
        case DriveBackupError.invalidFile:
            String(localized: "Mindrop couldn’t read this backup file.")
        default:
            error.localizedDescription
        }
    }
}

private extension UTType {
    static let mindropBackup = UTType(exportedAs: "mfsaglam.mindrop.backup", conformingTo: .data)
}
