import MindropCore
import SwiftUI
import UniformTypeIdentifiers

struct DriveBackupsView: View {
    let repository: MemoryRepository
    let session: MindropSession
    private var drive: DriveMemoryBackup { session.driveBackup }

    @AppStorage(Preference.automaticDriveBackup) private var automatic = Preference.automaticDriveBackupDefault
    @State private var status: DriveMemoryBackup.Status?
    @State private var statusError: String?
    @State private var isWorking = false
    @State private var showsImporter = false
    @State private var pendingRestore: DriveBackupSnapshot?
    @State private var message: String?

    var body: some View {
        MemorySheetForm {
            Section {
                Toggle("Automatic Backups", isOn: $automatic)
                    #if os(macOS)
                    .toggleStyle(.switch)
                    #endif
                    .tint(Color(.brandCobalt))
                    .disabled(isWorking)
                    .onChange(of: automatic) { _, enabled in
                        if enabled { Task { await enableAutomaticBackups() } }
                    }
                #if os(macOS)
                HStack {
                    Spacer()
                    restoreButton
                    backUpButton
                }
                .buttonStyle(.bordered)
                #else
                backUpButton
                restoreButton
                #endif
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mindrop checks for changes when you open the app and backs up at most once every 24 hours per device.")
                    Text("Mindrop keeps the three latest uploaded backups in this folder.")
                }
            }

            if !repository.backupDuplicates.isEmpty {
                Section {
                    NavigationLink("Review Duplicate Memories") {
                        BackupDuplicatesView(repository: repository)
                            .settingsBackButton()
                    }
                }
            }

            if session.cloudBackups.backups?.isEmpty == false {
                Section {
                    NavigationLink("Previous iCloud Backups") {
                        PreviousCloudBackupsView(repository: repository, cloud: session.cloudBackups)
                            .settingsBackButton()
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("iCloud Drive Backups")
        .inlineNavigationTitle()
        .task { try? await session.cloudBackups.refresh() }
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
            Button("Restore Backup") { apply(restore) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Restores missing active memories and saved folders. Earlier versions of changed memories are added as copies.")
        }
        .alert("iCloud Drive Backups", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private var backUpButton: some View {
        Button("Back Up Now") { Task { await create() } }
            .disabled(isWorking)
    }

    private var restoreButton: some View {
        Button("Restore from File") { showsImporter = true }
            .disabled(isWorking)
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

    private func enableAutomaticBackups() async {
        do {
            try await drive.authorizeCurrentAccount()
            session.refreshDriveBackups()
        } catch {
            message = description(for: error)
        }
        await refresh()
    }

    private func create() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await drive.authorizeCurrentAccount()
            let library = try repository.driveBackupLibrary()
            if library.isEmpty {
                message = String(localized: "Save a memory before creating a backup.")
            } else {
                try await drive.create(library: library, automatically: false)
                session.refreshDriveBackups()
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
            pendingRestore = try await drive.open(result.get())
        } catch {
            message = description(for: error)
        }
    }

    private func apply(_ restore: DriveBackupSnapshot) {
        do {
            let count = try repository.restoreDriveBackup(restore)
            message = count == 0
                ? String(localized: "Backup restored.")
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

private struct BackupDuplicatesView: View {
    let repository: MemoryRepository
    @State private var selectedIDs: Set<UUID> = []
    @State private var pending: [MemoryRepository.BackupDuplicate]?
    @State private var saveFailed = false

    var body: some View {
        let duplicates = repository.backupDuplicates
        let selected = duplicates.filter { selectedIDs.contains($0.id) }
        MemorySheetForm {
            if duplicates.isEmpty {
                Text("No matching copies found.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    Button("Select All") { selectedIDs = Set(duplicates.map(\.id)) }
                        .disabled(selected.count == duplicates.count)
                    ForEach(duplicates) { copy in
                        Toggle(isOn: Binding(
                            get: { selectedIDs.contains(copy.id) },
                            set: { enabled in
                                if enabled { selectedIDs.insert(copy.id) } else { selectedIDs.remove(copy.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(copy.keyword)
                                Text("Keep in \(repository.folders.title(for: copy.originalFolderID))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                    }
                } footer: {
                    Text("Select matching copies to move out of General.")
                }
                Section {
                    Button("Move to Recently Deleted", role: .destructive) { pending = selected }
                        .disabled(selected.isEmpty)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("Review Duplicate Memories")
        .inlineNavigationTitle()
        .confirmationDialog(
            "Move Selected Copies?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { copies in
            Button("Move to Recently Deleted", role: .destructive) {
                do {
                    _ = try repository.deleteBackupDuplicates(copies)
                    selectedIDs.subtract(copies.map(\.id))
                } catch {
                    saveFailed = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn’t save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }
}

private extension UTType {
    static let mindropBackup = UTType(exportedAs: "mfsaglam.mindrop.backup", conformingTo: .data)
}
