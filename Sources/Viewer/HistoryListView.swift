import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HistoryListView: View {
    let items: [ClipItem]
    @Binding var selectedID: PersistentIdentifier?
    var onItemTap: ((ClipItem) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedID) {
                ForEach(items) { item in
                    HistoryRow(item: item)
                        .tag(item.persistentModelID)
                        .id(item.persistentModelID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onItemTap?(item)
                        }
                }
            }
            .listStyle(.plain)
            .onChange(of: selectedID) { _, newID in
                if let id = newID {
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let item: ClipItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                    .font(.body)
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
