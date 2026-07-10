import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HistoryListView: View {
    let items: [ClipItem]
    @Bindable var viewerState: ViewerState
    var onItemTap: ((ClipItem) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        HistoryRowButton(
                            item: item,
                            viewerState: viewerState,
                            onItemTap: onItemTap
                        )
                        .id(item.persistentModelID)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .background {
                SelectionScroller(proxy: proxy, viewerState: viewerState)
            }
        }
    }
}

private struct SelectionScroller: View {
    let proxy: ScrollViewProxy
    @Bindable var viewerState: ViewerState

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .task(id: viewerState.selectedID) {
                guard let id = viewerState.selectedID else { return }
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                proxy.scrollTo(id, anchor: .center)
            }
    }
}

private struct HistoryRowButton: View {
    let item: ClipItem
    @Bindable var viewerState: ViewerState
    var onItemTap: ((ClipItem) -> Void)?

    private var isSelected: Bool {
        viewerState.selectedID == item.persistentModelID
    }

    var body: some View {
        Button {
            viewerState.selectedID = item.persistentModelID
            onItemTap?(item)
        } label: {
            HistoryRow(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HistoryRow: View {
    let item: ClipItem

    var body: some View {
        HStack {
            Text(item.title)
                .lineLimit(1)
                .font(.body)
            Spacer()
            if let label = typeLabel(for: item) {
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    // Check all available types, not just primaryType.
    // Browsers often put app-specific types first (e.g. org.chromium.web-custom-data),
    // with public.html as a secondary type.
    private func typeLabel(for item: ClipItem) -> String? {
        let uttypes = item.availableTypes.compactMap { UTType($0) }
        if uttypes.isEmpty { return nil }
        if uttypes.allSatisfy({ $0.conforms(to: .plainText) }) { return nil }
        if uttypes.contains(where: { $0.conforms(to: .rtf) || $0.conforms(to: .rtfd) }) { return "RTF" }
        if uttypes.contains(where: { $0.conforms(to: .html) }) { return "HTML" }
        if uttypes.contains(where: { $0.conforms(to: .pdf) }) { return "PDF" }
        if uttypes.contains(where: { $0.conforms(to: .image) }) { return "Image" }
        if uttypes.contains(where: { $0.conforms(to: .fileURL) }) { return "File" }
        return nil
    }
}
