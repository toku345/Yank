import SwiftData
import SwiftUI

extension SnippetEditorView {
    var folderColumn: some View {
        VStack(spacing: 0) {
            List(selection: folderSelection) {
                ForEach(orderedFolders) { folder in
                    folderRow(folder)
                }
                Color.clear
                    .frame(height: 8)
                    .dropDestination(for: SnippetEditorDragPayload.self) { payloads, _ in
                        handleFolderListEndDrop(payloads)
                    }
            }
            Divider()
            HStack {
                Button(action: beginCreateFolder) {
                    Label("New Folder", systemImage: "plus")
                }
                Button(action: beginImportClipyXML) {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button(action: beginRenameSelectedFolder) {
                    Label("Rename", systemImage: "pencil")
                }
                .disabled(selectedFolder == nil)
                Button(role: .destructive, action: deleteSelectedFolder) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedFolder == nil)
            }
            .labelStyle(.iconOnly)
            .padding(8)
        }
        .navigationTitle("Folders")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    func folderRow(_ folder: SnippetFolder) -> some View {
        Text(folder.title)
            .tag(folder.persistentModelID)
            .draggable(dragPayload(kind: .folder, id: folder.persistentModelID))
            .dropDestination(for: SnippetEditorDragPayload.self) { payloads, _ in
                handleFolderRowDrop(payloads, target: folder)
            }
            .contextMenu {
                Button("Rename") {
                    folderSheet = .rename(id: folder.persistentModelID, title: folder.title)
                }
                Button("Delete", role: .destructive) {
                    deleteFolder(folder)
                }
            }
    }

    @ViewBuilder
    var snippetColumn: some View {
        if let selectedFolder {
            VStack(spacing: 0) {
                snippetList(for: selectedFolder)
                Divider()
                HStack {
                    Button(action: beginCreateSnippet) {
                        Label("New Snippet", systemImage: "plus")
                    }
                    Spacer()
                    Button(role: .destructive, action: deleteSelectedSnippet) {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(state.selectedSnippetID == nil)
                }
                .labelStyle(.iconOnly)
                .padding(8)
            }
            .navigationTitle(selectedFolder.title)
            .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } else {
            ContentUnavailableView {
                Label("No Snippet Folders", systemImage: "folder")
            } description: {
                Text("Create a folder to organize snippets.")
            } actions: {
                Button("Create Folder", action: beginCreateFolder)
            }
        }
    }

    @ViewBuilder
    func snippetList(for folder: SnippetFolder) -> some View {
        if orderedSnippets.isEmpty {
            ContentUnavailableView {
                Label("No Snippets", systemImage: "text.quote")
            } description: {
                Text("Create a snippet in \(folder.title).")
            } actions: {
                Button("New Snippet", action: beginCreateSnippet)
            }
            .dropDestination(for: SnippetEditorDragPayload.self) { payloads, _ in
                handleSnippetListEndDrop(payloads, folder: folder)
            }
        } else {
            List(selection: snippetSelection) {
                ForEach(orderedSnippets) { snippet in
                    snippetRow(snippet)
                }
                Color.clear
                    .frame(height: 8)
                    .dropDestination(for: SnippetEditorDragPayload.self) { payloads, _ in
                        handleSnippetListEndDrop(payloads, folder: folder)
                    }
            }
        }
    }

    func snippetRow(_ snippet: Snippet) -> some View {
        Text(snippet.title)
            .tag(snippet.persistentModelID)
            .draggable(dragPayload(kind: .snippet, id: snippet.persistentModelID))
            .dropDestination(for: SnippetEditorDragPayload.self) { payloads, _ in
                handleSnippetRowDrop(payloads, target: snippet)
            }
            .contextMenu {
                moveMenu(for: snippet)
                Button("Delete", role: .destructive) {
                    deleteSnippet(snippet)
                }
            }
    }

    @ViewBuilder
    func moveMenu(for snippet: Snippet) -> some View {
        let destinations = orderedFolders.filter {
            $0.persistentModelID != snippet.folder?.persistentModelID
        }
        if destinations.isEmpty {
            Button("Move to Folder") {}
                .disabled(true)
        } else {
            Menu("Move to Folder") {
                ForEach(destinations) { folder in
                    Button(folder.title) {
                        requestMove(snippet: snippet, to: folder, before: nil)
                    }
                }
            }
        }
    }

    func dragPayload(
        kind: SnippetEditorDragItem.Kind,
        id: PersistentIdentifier
    ) -> SnippetEditorDragPayload {
        dragRegistry.payload(for: SnippetEditorDragItem(kind: kind, id: id))
    }
}
