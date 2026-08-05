import SwiftData
import SwiftUI

struct SnippetListView: View {
    let folders: [SnippetFolder]
    @Bindable var viewerState: ViewerState
    var onSnippetTap: ((Snippet) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(SnippetOrdering.folders(folders)) { folder in
                        SnippetFolderSection(
                            folder: folder,
                            viewerState: viewerState,
                            onSnippetTap: onSnippetTap
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .background {
                SnippetSelectionScroller(proxy: proxy, viewerState: viewerState)
            }
        }
    }
}

private struct SnippetFolderSection: View {
    let folder: SnippetFolder
    @Bindable var viewerState: ViewerState
    var onSnippetTap: ((Snippet) -> Void)?

    private var snippets: [Snippet] {
        SnippetOrdering.snippets(folder.snippets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(folder.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            if snippets.isEmpty {
                Text("No Snippets")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            } else {
                ForEach(snippets) { snippet in
                    SnippetRowButton(
                        snippet: snippet,
                        viewerState: viewerState,
                        onSnippetTap: onSnippetTap
                    )
                    .id(snippet.persistentModelID)
                }
            }
        }
    }
}

private struct SnippetSelectionScroller: View {
    let proxy: ScrollViewProxy
    @Bindable var viewerState: ViewerState

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .task(id: viewerState.selectedSnippetID) {
                guard let id = viewerState.selectedSnippetID else { return }
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

@MainActor
struct SnippetRowContract {
    let snippet: Snippet
    let viewerState: ViewerState
    let onActivate: ((Snippet) -> Void)?

    var accessibilityLabel: String {
        snippet.title
    }

    var isSelected: Bool {
        viewerState.selectedSnippetID == snippet.persistentModelID
    }

    func activate() {
        viewerState.selectedSnippetID = snippet.persistentModelID
        onActivate?(snippet)
    }
}

private struct SnippetRowButton: View {
    let snippet: Snippet
    @Bindable var viewerState: ViewerState
    var onSnippetTap: ((Snippet) -> Void)?

    var body: some View {
        let contract = SnippetRowContract(
            snippet: snippet,
            viewerState: viewerState,
            onActivate: onSnippetTap
        )

        Button(action: contract.activate) {
            Text(snippet.title)
                .lineLimit(1)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(contract.isSelected ? Color.accentColor.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text(contract.accessibilityLabel))
        .accessibilityAddTraits(contract.isSelected ? .isSelected : [])
    }
}
