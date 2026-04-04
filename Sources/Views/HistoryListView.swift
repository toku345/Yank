import SwiftUI
import SwiftData

struct HistoryListView: View {
    let items: [ClipItem]
    @Binding var selectedIndex: Int?
    let onPaste: (ClipItem) -> Void

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
        switch type {
        case let t where t.contains("rtf"): "RTF"
        case let t where t.contains("pdf"): "PDF"
        case let t where t.contains("tiff") || t.contains("png"): "Image"
        case let t where t.contains("file-url"): "File"
        default: "Other"
        }
    }
}
