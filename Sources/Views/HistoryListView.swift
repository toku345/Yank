import SwiftUI

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
            if !item.primaryType.contains("plain-text") && !item.primaryType.contains("string") {
                Text(typeLabel(item.primaryType))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func typeLabel(_ type: String) -> String {
        if type.contains("rtf") { return "RTF" }
        if type.contains("pdf") { return "PDF" }
        if type.contains("tiff") || type.contains("png") { return "Image" }
        if type.contains("file-url") { return "File" }
        return "Other"
    }
}
