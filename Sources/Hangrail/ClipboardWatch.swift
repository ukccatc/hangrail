import AppKit

/// Watches the general pasteboard and hangs new images or text when the option is on.
@MainActor
final class ClipboardWatch {
    static let shared = ClipboardWatch()

    private static let enabledKey = "hangClipboard"
    private var lastChange = NSPasteboard.general.changeCount
    /// Set after Hangrail itself writes the pasteboard, so that copy is not re-hung.
    private var ignoredChange: Int?

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func ignoreCurrent() {
        ignoredChange = NSPasteboard.general.changeCount
    }

    /// Called often. Returns a file URL when a new image or note should be hung.
    func poll() -> URL? {
        guard Self.isEnabled else { return nil }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return nil }
        lastChange = pasteboard.changeCount
        if ignoredChange == pasteboard.changeCount {
            ignoredChange = nil
            return nil
        }
        return stash(pasteboard)
    }

    private func stash(_ pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let image = urls.first(where: ImageDrop.isImage) {
            return image
        }
        let note = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        // A real snippet wins over the TIFF some apps attach to copied text.
        // A short caption next to an image stays an image.
        if let note, !note.isEmpty, imageData == nil || note.count > 40 || note.contains("\n") {
            return writeNote(note)
        }
        if let imageData {
            return writeImage(imageData, hasPNG: pasteboard.data(forType: .png) != nil)
        }
        return nil
    }

    private func writeNote(_ raw: String?) -> URL? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        let folder = Self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Note-\(UUID().uuidString).txt")
        do {
            try String(text.prefix(20_000)).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func writeImage(_ data: Data, hasPNG: Bool) -> URL? {
        let folder = Self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Clipboard-\(UUID().uuidString).png")
        let png: Data
        if hasPNG {
            png = data
        } else if let rep = NSBitmapImageRep(data: data),
                  let encoded = rep.representation(using: .png, properties: [:]) {
            png = encoded
        } else {
            return nil
        }
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static var folder: URL {
        Inbox.folder.deletingLastPathComponent().appendingPathComponent("Clipboard", isDirectory: true)
    }
}
