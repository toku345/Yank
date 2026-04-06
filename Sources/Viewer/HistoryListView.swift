import SwiftUI
import UniformTypeIdentifiers

struct HistoryListView: View {
    let items: [ClipItem]
    @Binding var selectedIndex: Int?

    var body: some View {
        List(selection: $selectedIndex) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HistoryRow(item: item)
                    .tag(index)
            }
        }
        .listStyle(.plain)
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

    private func typeLabel(for item: ClipItem) -> String? {
        guard let uttype = item.primaryUTType else { return nil }
        if uttype.conforms(to: .plainText) { return nil }
        if uttype.conforms(to: .rtf) || uttype.conforms(to: .rtfd) { return "RTF" }
        if uttype.conforms(to: .html) { return "HTML" }
        if uttype.conforms(to: .pdf) { return "PDF" }
        if uttype.conforms(to: .image) { return "Image" }
        if uttype.conforms(to: .fileURL) { return "File" }
        return nil
    }
}
