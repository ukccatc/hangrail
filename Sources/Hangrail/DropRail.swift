import AppKit
import SwiftUI

/// Image files a drag from Finder or the Desktop may hang on the rail.
enum ImageDrop {
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp",
    ]

    static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return [] }
        return urls.filter(isImage)
    }

    /// True while another app (not a drag that started on the rail) is
    /// dragging image files. Cheap when no drag is in progress.
    static func dragPasteboardHasImages() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.types?.contains(.fileURL) == true else { return false }
        return !fileURLs(from: pasteboard).isEmpty
    }
}

/// A full-width drop target over the rail. It only steals hits while an
/// image file is being dragged in, so ordinary clicks still reach the photos.
struct DropRail: NSViewRepresentable {
    let line: Line

    func makeNSView(context: Context) -> DropRailView {
        let view = DropRailView()
        view.onHover = { hovering in
            MainActor.assumeIsolated { line.receivingDrop = hovering }
        }
        view.onDrop = { urls in
            MainActor.assumeIsolated {
                line.receivingDrop = false
                for url in urls { line.hang(url) }
            }
        }
        return view
    }

    func updateNSView(_ view: DropRailView, context: Context) {}
}

final class DropRailView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// In front of the cards, but transparent to the mouse unless a file
    /// image is coming in from outside the app.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), acceptsExternalImages else { return nil }
        return self
    }

    private var acceptsExternalImages: Bool {
        !GrabView.isDragging && ImageDrop.dragPasteboardHasImages()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dropURLs(from: sender).isEmpty == false else { return [] }
        onHover(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onHover(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !dropURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = dropURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onHover(false)
        onDrop(urls)
        return true
    }

    private func dropURLs(from sender: NSDraggingInfo) -> [URL] {
        guard !GrabView.isDragging else { return [] }
        return ImageDrop.fileURLs(from: sender.draggingPasteboard)
    }
}
