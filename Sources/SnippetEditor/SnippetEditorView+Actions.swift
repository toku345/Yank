import SwiftData

extension SnippetEditorView {
    @discardableResult
    func requestTransition(_ transition: () -> Void) -> Bool {
        do {
            let resolved = try state.resolveDirtyDraft(
                decisionProvider: dirtyDraftPrompt,
                in: modelContext
            )
            guard resolved else { return false }
            transition()
            return true
        } catch {
            errorReporter("save the snippet", error)
            return false
        }
    }

    func beginCreateFolder() {
        requestTransition {
            folderSheet = .create
        }
    }

    func beginRenameSelectedFolder() {
        guard let selectedFolder else { return }
        folderSheet = .rename(id: selectedFolder.persistentModelID, title: selectedFolder.title)
    }

    func createFolder(title: String) -> Bool {
        performMutation("create the folder") {
            let result = try SnippetMutations.createFolder(title: title, in: modelContext)
            try state.apply(result, in: modelContext)
        }
    }

    func renameFolder(id: PersistentIdentifier, title: String) -> Bool {
        performMutation("rename the folder") {
            try SnippetMutations.renameFolder(id: id, title: title, in: modelContext)
        }
    }

    func deleteSelectedFolder() {
        guard let selectedFolder else { return }
        deleteFolder(selectedFolder)
    }

    func deleteFolder(_ folder: SnippetFolder) {
        let snippetCount = folder.snippets.count
        let message = snippetCount == 1
            ? "This permanently deletes the folder and its 1 snippet."
            : "This permanently deletes the folder and its \(snippetCount) snippets."
        guard deleteConfirmation("Delete “\(folder.title)”?", message) else { return }
        let wasSelected = state.selectedFolderID == folder.persistentModelID
        let deletion = {
            performMutation("delete the folder") {
                let result = try SnippetMutations.deleteFolder(id: folder.persistentModelID, in: modelContext)
                if wasSelected {
                    try state.apply(result, in: modelContext)
                }
            }
        }
        if wasSelected && state.hasDirtyDraft {
            requestTransition {
                _ = deletion()
            }
        } else {
            _ = deletion()
        }
    }

    func beginCreateSnippet() {
        guard let selectedFolder else { return }
        requestTransition {
            state.beginNewSnippet(in: selectedFolder)
        }
    }

    func saveDraft() {
        performMutation("save the snippet") {
            try state.saveDraft(in: modelContext)
        }
    }

    func discardDraft() {
        performMutation("discard the snippet changes") {
            try state.discardDraft(in: modelContext)
        }
    }

    func deleteSelectedSnippet() {
        guard let selectedSnippetID = state.selectedSnippetID,
              let snippet = orderedSnippets.first(where: { $0.persistentModelID == selectedSnippetID }) else { return }
        deleteSnippet(snippet)
    }

    func deleteSnippet(_ snippet: Snippet) {
        guard deleteConfirmation("Delete “\(snippet.title)”?", "This permanently deletes the snippet.") else { return }
        let wasSelected = state.selectedSnippetID == snippet.persistentModelID
        let deletion = {
            performMutation("delete the snippet") {
                let result = try SnippetMutations.deleteSnippet(id: snippet.persistentModelID, in: modelContext)
                if wasSelected {
                    try state.apply(result, in: modelContext)
                }
            }
        }
        if wasSelected && state.hasDirtyDraft {
            requestTransition {
                _ = deletion()
            }
        } else {
            _ = deletion()
        }
    }

    @discardableResult
    func requestMove(snippet: Snippet, to folder: SnippetFolder, before targetID: PersistentIdentifier?) -> Bool {
        var succeeded = false
        let action: () -> Void = {
            succeeded = performMutation("move the snippet") {
                let result = try SnippetMutations.moveSnippet(
                    id: snippet.persistentModelID,
                    to: folder.persistentModelID,
                    before: targetID,
                    in: modelContext
                )
                if state.selectedSnippetID == snippet.persistentModelID, let result {
                    try state.apply(result, in: modelContext)
                }
            }
        }
        if state.selectedSnippetID == snippet.persistentModelID && state.hasDirtyDraft {
            guard requestTransition(action) else { return false }
        } else {
            action()
        }
        return succeeded
    }

    func handleFolderRowDrop(_ payloads: [SnippetEditorDragPayload], target: SnippetFolder) -> Bool {
        guard let payload = payloads.first,
              let item = dragRegistry.resolve(payload) else { return false }
        switch item.kind {
        case .folder:
            return performMutation("reorder the folders") {
                try SnippetMutations.moveFolder(id: item.id, before: target.persistentModelID, in: modelContext)
            }
        case .snippet:
            guard let snippet = snippet(id: item.id) else { return false }
            return requestMove(snippet: snippet, to: target, before: nil)
        }
    }

    func handleFolderListEndDrop(_ payloads: [SnippetEditorDragPayload]) -> Bool {
        guard let payload = payloads.first,
              let item = dragRegistry.resolve(payload),
              item.kind == .folder else { return false }
        return performMutation("reorder the folders") {
            try SnippetMutations.moveFolder(id: item.id, before: nil, in: modelContext)
        }
    }

    func handleSnippetRowDrop(_ payloads: [SnippetEditorDragPayload], target: Snippet) -> Bool {
        guard let payload = payloads.first,
              let item = dragRegistry.resolve(payload),
              item.kind == .snippet,
              let snippet = snippet(id: item.id),
              let folder = target.folder else { return false }
        return requestMove(snippet: snippet, to: folder, before: target.persistentModelID)
    }

    func handleSnippetListEndDrop(_ payloads: [SnippetEditorDragPayload], folder: SnippetFolder) -> Bool {
        guard let payload = payloads.first,
              let item = dragRegistry.resolve(payload),
              item.kind == .snippet,
              let snippet = snippet(id: item.id) else { return false }
        return requestMove(snippet: snippet, to: folder, before: nil)
    }

    func snippet(id: PersistentIdentifier) -> Snippet? {
        do {
            return try modelContext.fetch(FetchDescriptor<Snippet>()).first { $0.persistentModelID == id }
        } catch {
            errorReporter("load the dragged snippet", error)
            return nil
        }
    }

    @discardableResult
    func performMutation(_ operation: String, _ mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            return true
        } catch {
            errorReporter(operation, error)
            return false
        }
    }
}
