import Foundation

/// Reads and writes a single file in the App Group container under file coordination,
/// so the app and the share extension cannot tear each other's writes.
struct CoordinatedFile: Sendable {
    let url: URL

    /// Returns `nil` when the file does not exist yet.
    func read() throws -> Data? {
        var coordinatorError: NSError?
        var result: Result<Data?, Error> = .success(nil)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                result = .success(try Data(contentsOf: url))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { url in
            do {
                try data.write(to: url, options: .atomic)
                #if os(iOS)
                // Encrypt at rest while the device is locked. `completeUnlessOpen` keeps an
                // already-open handle usable, which avoids surprising write failures.
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen],
                    ofItemAtPath: url.path
                )
                #endif
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }
}
