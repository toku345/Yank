import SwiftData
import SwiftUI

struct SnippetCollectionSnapshot: Equatable {
    let folderID: PersistentIdentifier
    let title: String
    let sortOrder: Int
    let snippetIDs: [PersistentIdentifier]
}

enum FolderEditorSheet: Identifiable {
    case create
    case rename(id: PersistentIdentifier, title: String)

    var id: String {
        switch self {
        case .create:
            "create"
        case .rename(let id, _):
            "rename-\(id)"
        }
    }
}

struct SnippetEditorView: View {
    @Environment(\.modelContext)
    var modelContext

    @Query(sort: \SnippetFolder.sortOrder)
    var folders: [SnippetFolder]

    @Bindable var state: SnippetEditorState
    @State var folderSheet: FolderEditorSheet?

    let dirtyDraftPrompt: SnippetEditorWindowController.DirtyDraftPrompt
    let deleteConfirmation: SnippetEditorWindowController.DeleteConfirmation
    let errorReporter: SnippetEditorWindowController.ErrorReporter

    var body: some View {
        NavigationSplitView {
            folderColumn
        } content: {
            snippetColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            state.synchronize(with: orderedFolders)
        }
        .onChange(of: collectionSnapshot) {
            state.synchronize(with: orderedFolders)
        }
        .sheet(item: $folderSheet) { sheet in
            folderEditorSheet(sheet)
        }
    }

    var orderedFolders: [SnippetFolder] {
        SnippetOrdering.folders(folders)
    }

    var selectedFolder: SnippetFolder? {
        guard let selectedFolderID = state.selectedFolderID else { return nil }
        return orderedFolders.first { $0.persistentModelID == selectedFolderID }
    }

    var orderedSnippets: [Snippet] {
        guard let selectedFolder else { return [] }
        return SnippetOrdering.snippets(selectedFolder.snippets)
    }

    private var collectionSnapshot: [SnippetCollectionSnapshot] {
        orderedFolders.map { folder in
            SnippetCollectionSnapshot(
                folderID: folder.persistentModelID,
                title: folder.title,
                sortOrder: folder.sortOrder,
                snippetIDs: SnippetOrdering.snippets(folder.snippets).map(\.persistentModelID)
            )
        }
    }

    var folderSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: { state.selectedFolderID },
            set: { newID in
                guard let newID,
                      let folder = orderedFolders.first(where: { $0.persistentModelID == newID }),
                      newID != state.selectedFolderID else { return }
                requestTransition {
                    state.selectFolder(folder)
                }
            }
        )
    }

    var snippetSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: { state.selectedSnippetID },
            set: { newID in
                guard let newID,
                      let snippet = orderedSnippets.first(where: { $0.persistentModelID == newID }),
                      newID != state.selectedSnippetID else { return }
                requestTransition {
                    state.selectSnippet(snippet)
                }
            }
        )
    }

    @ViewBuilder
    private var detailColumn: some View {
        if state.draft != nil {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: draftTitle)
                TextEditor(text: draftContent)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(.separator)
                if draftTitle.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("A title is required.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button(draftSecondaryButtonTitle, action: discardDraft)
                    Button("Save", action: saveDraft)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!canSaveDraft)
                }
            }
            .padding()
            .navigationTitle("Snippet")
        } else if selectedFolder == nil {
            ContentUnavailableView(
                "No Snippet Folders",
                systemImage: "folder",
                description: Text("Create a folder to begin.")
            )
        } else {
            ContentUnavailableView(
                "No Snippet Selected",
                systemImage: "text.quote",
                description: Text("Select a snippet or create a new one.")
            )
        }
    }

    private var draftTitle: Binding<String> {
        Binding(
            get: { state.draft?.title ?? "" },
            set: { state.draft?.title = $0 }
        )
    }

    private var draftContent: Binding<String> {
        Binding(
            get: { state.draft?.content ?? "" },
            set: { state.draft?.content = $0 }
        )
    }

    private var canSaveDraft: Bool {
        guard let draft = state.draft else { return false }
        return draft.isDirty && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draftSecondaryButtonTitle: String {
        guard let draft = state.draft else { return "Cancel" }
        if case .new = draft.kind {
            return "Cancel"
        }
        return "Revert"
    }

    @ViewBuilder
    private func folderEditorSheet(_ sheet: FolderEditorSheet) -> some View {
        switch sheet {
        case .create:
            FolderNameSheet(title: "New Folder", initialTitle: "", actionTitle: "Create") { title in
                createFolder(title: title)
            }
        case .rename(let id, let title):
            FolderNameSheet(title: "Rename Folder", initialTitle: title, actionTitle: "Rename") { newTitle in
                renameFolder(id: id, title: newTitle)
            }
        }
    }

}
