import AVKit
import SwiftUI

@MainActor
@Observable
final class HistoryViewState {
    var kind: CaptureKind = .recording
    var selection: Set<URL> = []
    var showInspector = true
    var searchText = ""
}

struct HistoryView: View {
    let history: HistoryStore
    @Bindable var state: HistoryViewState
    let onEdit: (CaptureItem) -> Void
    let onCopyText: (CaptureItem) -> Void
    let onPin: (CaptureItem) -> Void
    let onTrim: (CaptureItem) -> Void

    private var items: [CaptureItem] {
        let all = history.items(for: state.kind)
        guard !state.searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(state.searchText) }
    }

    private var selectedItems: [CaptureItem] {
        items.filter { state.selection.contains($0.url) }
    }

    var body: some View {
        content
            .frame(minWidth: 640, minHeight: 420)
            .navigationTitle(state.kind.historyTitle)
            .searchable(text: $state.searchText, placement: .toolbar, prompt: "Search \(state.kind.historyTitle)")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Type", selection: $state.kind) {
                        Label("Recordings", systemImage: "video").tag(CaptureKind.recording)
                        Label("Screenshots", systemImage: "photo").tag(CaptureKind.screenshot)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleAndIcon)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Open Folder", systemImage: "folder") {
                        NSWorkspace.shared.open(StorageManager.folder(for: state.kind))
                    }
                    Button("Delete", systemImage: "trash") { history.delete(selectedItems) }
                        .disabled(selectedItems.isEmpty)
                    Button("Inspector", systemImage: "sidebar.trailing") { state.showInspector.toggle() }
                }
            }
            .inspector(isPresented: $state.showInspector) {
                InspectorView(item: selectedItems.count == 1 ? selectedItems.first : nil, history: history, onEdit: onEdit)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .onChange(of: state.kind) { state.selection = [] }
            .onDeleteCommand { history.delete(selectedItems) }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label(state.searchText.isEmpty ? "No \(state.kind.historyTitle)" : "No Results",
                      systemImage: state.kind == .recording ? "video.slash" : "photo.on.rectangle")
            } description: {
                Text(state.searchText.isEmpty
                     ? "Your \(state.kind.historyTitle.lowercased()) are saved to Documents/ScreenCapture/\(state.kind == .recording ? "videos" : "images")."
                     : "Try a different search.")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)],
                          alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.items) { item in
                                HistoryCard(item: item, isSelected: state.selection.contains(item.url))
                                    .onTapGesture(count: 2) { open(item) }
                                    .onTapGesture { select(item) }
                                    .contextMenu { contextMenu(for: item) }
                                    .draggable(item.url)
                            }
                        } header: {
                            Text(section.title)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .background(.bar)
                        }
                    }
                }
                .padding(20)
            }
            .background {
                Color.clear.contentShape(.rect).onTapGesture { state.selection = [] }
            }
        }
    }

    private func select(_ item: CaptureItem) {
        if NSEvent.modifierFlags.contains(.command) {
            if state.selection.contains(item.url) { state.selection.remove(item.url) } else { state.selection.insert(item.url) }
        } else {
            state.selection = [item.url]
        }
    }

    private func open(_ item: CaptureItem) {
        if item.kind == .screenshot { onEdit(item) } else { NSWorkspace.shared.open(item.url) }
    }

    @ViewBuilder
    private func contextMenu(for item: CaptureItem) -> some View {
        if item.kind == .screenshot {
            Button("Edit…") { onEdit(item) }
        } else {
            Button("Trim…") { onTrim(item) }
        }
        Button("Open") { NSWorkspace.shared.open(item.url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Button("Copy") { copy(item) }
        if item.kind == .screenshot {
            Button("Copy Text") { onCopyText(item) }
            Button("Pin to Screen") { onPin(item) }
        }
        ShareLink(item: item.url)
        Divider()
        Button("Move to Trash", role: .destructive) {
            let targets = state.selection.contains(item.url) ? selectedItems : [item]
            history.delete(targets)
        }
    }

    private var sections: [(title: String, items: [CaptureItem])] {
        let calendar = Calendar.current
        var today: [CaptureItem] = [], yesterday: [CaptureItem] = [], week: [CaptureItem] = [], older: [CaptureItem] = []
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        for item in items {
            if calendar.isDateInToday(item.date) { today.append(item) }
            else if calendar.isDateInYesterday(item.date) { yesterday.append(item) }
            else if item.date > weekAgo { week.append(item) }
            else { older.append(item) }
        }
        return [("Today", today), ("Yesterday", yesterday), ("Previous 7 Days", week), ("Earlier", older)]
            .filter { !$0.1.isEmpty }
    }
}

func copy(_ item: CaptureItem) {
    NSPasteboard.general.clearContents()
    if item.kind == .screenshot, let image = NSImage(contentsOf: item.url) {
        NSPasteboard.general.writeObjects([item.url as NSURL])
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = ScreenshotService.pngData(cg) {
            NSPasteboard.general.setData(png, forType: .png)
        }
    } else {
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }
}

private struct HistoryCard: View {
    let item: CaptureItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(url: item.url, version: item.modified, maxPixel: 400)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if item.kind == .recording { DurationBadge(url: item.url, version: item.modified).padding(6) }
                }
                .overlay(alignment: .center) {
                    if item.kind == .recording {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .glassEffect(.regular, in: .circle)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.date.formatted(date: .omitted, time: .shortened)) · \(item.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(.rect(cornerRadius: 14))
    }
}

private struct InspectorView: View {
    let item: CaptureItem?
    let history: HistoryStore
    let onEdit: (CaptureItem) -> Void

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PreviewPane(item: item)
                        .id(item.url)
                    Text(item.name)
                        .font(.headline)
                        .textSelection(.enabled)
                    MetadataView(item: item)
                    VStack(spacing: 8) {
                        if item.kind == .screenshot {
                            Button {
                                onEdit(item)
                            } label: {
                                Label("Edit & Annotate", systemImage: "pencil.and.scribble")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                        }
                        HStack {
                            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(item.url) }
                            Button("Show in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                        HStack {
                            Button("Copy", systemImage: "doc.on.doc") { copy(item) }
                            ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
                            Button("Delete", systemImage: "trash", role: .destructive) { history.delete([item]) }
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "square.dashed",
                                   description: Text("Select an item to preview it."))
        }
    }
}

private struct PreviewPane: View {
    let item: CaptureItem
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if item.kind == .recording {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ThumbnailView(url: item.url, version: item.modified, maxPixel: 600, contentMode: .fit)
                }
            } else {
                ThumbnailView(url: item.url, version: item.modified, maxPixel: 900, contentMode: .fit)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 10))
        .task(id: item.url) {
            guard item.kind == .recording else { return }
            player = AVPlayer(url: item.url)
        }
        .onDisappear { player?.pause() }
    }
}

private struct MetadataView: View {
    let item: CaptureItem
    @State private var dimensions: String?
    @State private var duration: String?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Created", item.date.formatted(date: .abbreviated, time: .standard))
            row("Size", item.formattedSize)
            row("Format", item.url.pathExtension.uppercased())
            if let dimensions { row("Dimensions", dimensions) }
            if let duration { row("Duration", duration) }
        }
        .font(.caption)
        .task(id: item.url) { await load() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func load() async {
        dimensions = nil
        duration = nil
        if item.kind == .recording {
            let asset = AVURLAsset(url: item.url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize) {
                let fps = (try? await track.load(.nominalFrameRate)) ?? 0
                dimensions = "\(Int(size.width))×\(Int(size.height)) @ \(Int(fps.rounded())) fps"
            }
            duration = await ThumbnailCache.shared.duration(for: item.url)?.durationString
        } else if let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            dimensions = "\(w)×\(h)"
        }
    }
}
