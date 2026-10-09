import AppKit
import Foundation

enum ArchiveStore {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Hangrail/Archive", isDirectory: true)
    }()
}

/// One screenshot kept off the rail, still on this Mac.
struct ArchiveEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var archivedAt: Date
    var text: String

    var url: URL { ArchiveStore.folder.appendingPathComponent(filename) }
}

/// Local archive. Files are copied here so a full rail does not throw shots away.
@MainActor
final class Archive: ObservableObject {
    static let shared = Archive()

    @Published private(set) var entries: [ArchiveEntry] = []

    static var folder: URL { ArchiveStore.folder }

    private static let indexURL = ArchiveStore.folder.appendingPathComponent("index.json")
    private static let cleanupKey = "archiveCleanup"
    /// Shots older than this leave the archive when cleanup is on.
    static let cleanupDays = 7

    static var autoCleanup: Bool {
        get { UserDefaults.standard.bool(forKey: cleanupKey) }
        set { UserDefaults.standard.set(newValue, forKey: cleanupKey) }
    }

    private init() {
        load()
        if Self.autoCleanup { sweep() }
    }

    /// Copy `source` into the archive. Returns nil if the copy fails.
    @discardableResult
    func keep(_ source: URL, text: String = "") -> ArchiveEntry? {
        let fm = FileManager.default
        let sourcePath = source.standardizedFileURL.path
        let archivePrefix = ArchiveStore.folder.standardizedFileURL.path + "/"
        if sourcePath.hasPrefix(archivePrefix) {
            return entries.first { $0.filename == source.lastPathComponent }
        }
        do {
            try fm.createDirectory(at: ArchiveStore.folder, withIntermediateDirectories: true)
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let name = UUID().uuidString + "." + ext
            let dest = ArchiveStore.folder.appendingPathComponent(name)
            // Inbox and clipboard files belong to Hangrail, so move them.
            // A Desktop or Finder file is only copied; the original stays put.
            let inboxPrefix = Inbox.folder.standardizedFileURL.path + "/"
            let clipPrefix = ClipboardWatch.folder.standardizedFileURL.path + "/"
            if sourcePath.hasPrefix(inboxPrefix) || sourcePath.hasPrefix(clipPrefix) {
                try fm.moveItem(at: source, to: dest)
            } else {
                try fm.copyItem(at: source, to: dest)
            }
            let entry = ArchiveEntry(id: UUID(), filename: name, archivedAt: Date(), text: text)
            entries.insert(entry, at: 0)
            save()
            if text.isEmpty {
                let id = entry.id
                ShotText.recognize(dest) { [weak self] found in
                    self?.updateText(id: id, text: found)
                }
            }
            return entry
        } catch {
            log.error("Could not archive \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func updateText(id: UUID, text: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].text = text
        save()
    }

    /// Drop the index row when the file is trashed from the rail. Does not delete the file.
    func forget(_ url: URL) {
        let path = url.standardizedFileURL.path
        let before = entries.count
        entries.removeAll { $0.url.standardizedFileURL.path == path }
        if entries.count != before { save() }
    }

    func trash(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let url = entries[i].url
        entries.remove(at: i)
        save()
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// Drop archive files older than `cleanupDays`. No-op when the option is off.
    func sweep() {
        guard Self.autoCleanup else { return }
        let cutoff = Date().addingTimeInterval(-Double(Self.cleanupDays) * 86_400)
        let stale = entries.filter { $0.archivedAt < cutoff }
        for entry in stale { trash(entry.id) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([ArchiveEntry].self, from: data) else { return }
        entries = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }
}
