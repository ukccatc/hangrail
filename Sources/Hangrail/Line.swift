import AppKit
import Combine
import os

let log = Logger(subsystem: "app.hangrail.Hangrail", category: "line")

/// One screenshot hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumb: NSImage
    /// Where it hangs on the rail, 0 = left margin, 1 = right margin.
    var place: CGFloat
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false
    /// Pinned cards stay on the rail when a new shot would otherwise push them off.
    var pinned = false
    /// When it was hung. Overflow archives the oldest unpinned card.
    var hungAt = Date()
    /// Copied text, shown as a note on the rail. Nil for screenshots.
    var note: String?

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying
            && a.place == b.place && a.thumb === b.thumb && a.pinned == b.pinned
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    /// The photo being slid along the rail.
    @Published var reorderID: UUID?
    /// Its place when the slide started, so motion follows the finger.
    private var slideStartPlace: CGFloat = 0
    /// Whether the line has slid down into view.
    @Published var revealed = false
    /// An image file is hovering the rail and can be hung.
    @Published var receivingDrop = false

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]

    var maxItems = 8


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let storeKey = "pegged"
    private let placeStoreKey = "peggedPlaces"
    private let pinStoreKey = "peggedPins"
    private let hungStoreKey = "peggedHungAt"
    private let textStoreKey = "peggedText"
    /// Recognized text for shots still on the rail, keyed by file path.
    private var texts: [String: String] = [:]

    init() {
        texts = UserDefaults.standard.dictionary(forKey: textStoreKey) as? [String: String] ?? [:]
        restore()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false, place: CGFloat? = nil, pinned: Bool = false, hungAt: Date = Date()) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return nil }
        var item = Pegged(url: url, thumb: thumb, place: place ?? nextPlace())
        item.flying = flying
        item.pinned = pinned
        item.hungAt = hungAt
        item.note = noteText(url)
        items.append(item)
        if noteText(url) != nil { rememberNote(url) }
        makeRoom()
        sortByPlace()
        save()
        if !quietly { play("Tink", volume: 0.35) }
        if noteText(url) == nil { recognize(url) }
        return item.id
    }

    /// A full rail archives the oldest unpinned shot. Pins stay, even if that
    /// leaves more cards than maxItems. If every card is pinned, stop.
    private func makeRoom() {
        while liveCount > maxItems {
            guard let oldest = items.filter({ !$0.falling && !$0.pinned }).min(by: { $0.hungAt < $1.hungAt }) else { break }
            let text = texts[oldest.url.path] ?? ""
            Archive.shared.keep(oldest.url, text: text)
            drop(oldest.id, quietly: true)
        }
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
        if !items[i].pinned { makeRoom() }
    }

    func share(_ id: UUID, from view: NSView) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let picker = NSSharingServicePicker(items: [item.url as NSURL])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func matching(_ query: String) -> [Pegged] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return items.filter { !$0.falling && texts[$0.url.path]?.localizedCaseInsensitiveContains(q) == true }
    }

    private func rememberNote(_ url: URL) {
        guard let text = noteText(url), !text.isEmpty else { return }
        texts[url.path] = text
        UserDefaults.standard.set(texts, forKey: textStoreKey)
    }

    private func recognize(_ url: URL) {
        ShotText.recognize(url) { [weak self] text in
            guard let self, !text.isEmpty else { return }
            self.texts[url.path] = text
            UserDefaults.standard.set(self.texts, forKey: self.textStoreKey)
        }
    }

    /// Prefer the centre, then alternate left/right with a gap, staying inside
    /// the side insets. Manual placements are left alone.
    private func nextPlace() -> CGFloat {
        let live = items.filter { !$0.falling }
        let inset = Layout.placeInset
        let step = Layout.placeStep
        guard !live.isEmpty else { return 0.5 }
        let taken = live.map(\.place)
        var candidates: [CGFloat] = [0.5]
        for n in 1...max(maxItems, 8) {
            let d = CGFloat(n) * step
            candidates.append(0.5 + d)
            candidates.append(0.5 - d)
        }
        for raw in candidates {
            let place = min(1 - inset, max(inset, raw))
            if taken.allSatisfy({ abs($0 - place) >= step * 0.85 }) {
                return place
            }
        }
        return min(1 - inset, (taken.max() ?? 0.5) + step)
    }

    private func sortByPlace() {
        items.sort { a, b in
            if a.falling != b.falling { return !a.falling && b.falling }
            return a.place < b.place
        }
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        items[i].falling = true
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func clear() {
        let live = items.filter { !$0.falling }
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.drop(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
    }

    // MARK: Arranging

    /// Follow the pointer along the rail. Any place between the left and
    /// right margins is valid; cards are not snapped to slots.
    func slide(_ id: UUID, translationX: CGFloat, panelWidth: CGFloat) {
        guard panelWidth > 1, let from = items.firstIndex(where: { $0.id == id }),
              !items[from].falling else { return }
        if reorderID != id {
            reorderID = id
            slideStartPlace = items[from].place
        }
        let place = min(1, max(0, slideStartPlace + translationX / Layout.usableWidth(panelWidth)))
        guard items[from].place != place else { return }
        items[from].place = place
    }

    func endSlide() {
        if reorderID != nil {
            sortByPlace()
            save()
        }
        clearSlide()
    }

    func cancelSlide() {
        if let id = reorderID, let i = items.firstIndex(where: { $0.id == id }) {
            items[i].place = slideStartPlace
        }
        clearSlide()
    }

    private func clearSlide() {
        reorderID = nil
        slideStartPlace = 0
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let text = noteText(item.url) {
            pb.setString(text, forType: .string)
        } else {
            let entry = NSPasteboardItem()
            if let png = pngData(item.url) { entry.setData(png, forType: .png) }
            entry.setString(item.url.absoluteString, forType: .fileURL)
            pb.writeObjects([entry])
        }
        ClipboardWatch.shared.ignoreCurrent()

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(item.url)
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    func trash(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        Archive.shared.forget(item.url)
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn { Line.trashSound?.play() }
            drop(id, quietly: true)
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Hangrail's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here.
    func discard(_ id: UUID) {
        if isInInbox(id) { trash(id) } else { drop(id) }
    }

    /// Inbox mode: keep a screenshot by moving it to the Desktop.
    func saveToDesktop(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            drop(id, quietly: true)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        Markup.shared.edit(item.url)
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].thumb = thumb
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil && self.reorderID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let live = items.filter { !$0.falling }
        UserDefaults.standard.set(live.map(\.url.path), forKey: storeKey)
        let places = Dictionary(uniqueKeysWithValues: live.map { ($0.url.path, Double($0.place)) })
        UserDefaults.standard.set(places, forKey: placeStoreKey)
        let pins = Dictionary(uniqueKeysWithValues: live.map { ($0.url.path, $0.pinned) })
        UserDefaults.standard.set(pins, forKey: pinStoreKey)
        let hung = Dictionary(uniqueKeysWithValues: live.map { ($0.url.path, $0.hungAt.timeIntervalSince1970) })
        UserDefaults.standard.set(hung, forKey: hungStoreKey)
    }

    private func restore() {
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        let places = UserDefaults.standard.dictionary(forKey: placeStoreKey) as? [String: Double] ?? [:]
        let pins = UserDefaults.standard.dictionary(forKey: pinStoreKey) as? [String: Bool] ?? [:]
        let hung = UserDefaults.standard.dictionary(forKey: hungStoreKey) as? [String: Double] ?? [:]
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let count = existing.count
        let start = count <= 1 ? 0.5
            : max(Layout.placeInset, 0.5 - CGFloat(count - 1) * Layout.placeStep / 2)
        for (index, path) in existing.enumerated() {
            let seeded: CGFloat
            if let saved = places[path] {
                seeded = CGFloat(saved)
            } else {
                seeded = min(1 - Layout.placeInset, start + CGFloat(index) * Layout.placeStep)
            }
            let when = hung[path].map { Date(timeIntervalSince1970: $0) } ?? Date()
            hang(URL(fileURLWithPath: path), quietly: true, place: seeded, pinned: pins[path] ?? false, hungAt: when)
        }
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

func noteText(_ url: URL) -> String? {
    guard url.pathExtension.lowercased() == "txt" else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

func makeThumbnail(_ url: URL, maxPixels: Int = 480) -> NSImage? {
    if let text = noteText(url) { return noteThumbnail(text) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

/// A portrait slip so copied text hangs on the same rail as screenshots.
/// Short notes use a large face; longer notes shrink until the text fits.
func noteThumbnail(_ text: String) -> NSImage {
    let size = NSSize(width: 360, height: 480)
    let textRect = NSRect(x: 64, y: 28, width: size.width - 84, height: size.height - 52)
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let fontSize = noteFontSize(body, fitting: textRect)
    let image = NSImage(size: size)
    image.lockFocusFlipped(true)
    NSGradient(colors: [
        NSColor(srgbRed: 242 / 255, green: 226 / 255, blue: 196 / 255, alpha: 1),
        NSColor(srgbRed: 222 / 255, green: 196 / 255, blue: 156 / 255, alpha: 1),
    ])?.draw(in: NSRect(origin: .zero, size: size), angle: -90)
    let rule = NSColor(srgbRed: 196 / 255, green: 118 / 255, blue: 42 / 255, alpha: 0.28)
    rule.setFill()
    for row in 1..<8 {
        let y = 36 + CGFloat(row) * 52
        NSBezierPath(rect: NSRect(x: 18, y: y, width: size.width - 36, height: 1)).fill()
    }
    NSColor(srgbRed: 232 / 255, green: 165 / 255, blue: 75 / 255, alpha: 0.7).setFill()
    NSBezierPath(rect: NSRect(x: 48, y: 0, width: 2, height: size.height)).fill()
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: fontSize > 40 ? .semibold : .medium),
        .foregroundColor: NSColor(srgbRed: 13 / 255, green: 21 / 255, blue: 32 / 255, alpha: 1),
        .paragraphStyle: style,
    ]
    (body as NSString).draw(
        with: textRect,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attrs)
    image.unlockFocus()
    return image
}

/// Largest size whose wrapped height still sits inside `rect`.
private func noteFontSize(_ text: String, fitting rect: NSRect) -> CGFloat {
    let sample = text.isEmpty ? " " : text
    var low: CGFloat = 18
    var high: CGFloat = 92
    var best = low
    while high - low > 1 {
        let mid = (low + high) / 2
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let bounds = (sample as NSString).boundingRect(
            with: NSSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: mid, weight: mid > 40 ? .semibold : .medium),
                .paragraphStyle: style,
            ])
        if bounds.height <= rect.height {
            best = mid
            low = mid
        } else {
            high = mid
        }
    }
    return best
}
