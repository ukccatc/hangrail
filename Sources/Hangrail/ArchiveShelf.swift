import SwiftUI

/// A small shelf of archived shots: search, open, put back on the rail, or trash.
struct ArchiveShelf: View {
    @ObservedObject var archive: Archive
    let line: Line
    @State private var query = ""

    private var shown: [ArchiveEntry] {
        let base = archive.entries
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = q.isEmpty ? base : base.filter {
            $0.text.localizedCaseInsensitiveContains(q) || $0.filename.localizedCaseInsensitiveContains(q)
        }
        return Array(filtered.prefix(48))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("Search screenshots"), text: $query)
                .textFieldStyle(.roundedBorder)
            if shown.isEmpty && line.matching(query).isEmpty {
                Text(query.isEmpty ? L("Nothing in the archive") : L("No matches"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if !line.matching(query).isEmpty {
                        Text(L("On the line"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                            ForEach(line.matching(query)) { item in
                                Button {
                                    NSWorkspace.shared.open(item.url)
                                } label: {
                                    Image(nsImage: item.thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 78)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(shown) { entry in
                            card(entry)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 420, minHeight: 320)
    }

    private func card(_ entry: ArchiveEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            thumb(entry)
                .frame(height: 78)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 6) {
                Button(L("Open")) { NSWorkspace.shared.open(entry.url) }
                Button(L("Restore to line")) { line.hang(entry.url) }
                Button(L("Move to Trash")) { archive.trash(entry.id) }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func thumb(_ entry: ArchiveEntry) -> some View {
        if entry.url.pathExtension.lowercased() == "txt" {
            NoteSlip(text: entry.text.isEmpty ? (noteText(entry.url) ?? "") : entry.text, compact: true)
        } else if let image = makeThumbnail(entry.url, maxPixels: 240) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.black.opacity(0.08)
        }
    }
}
