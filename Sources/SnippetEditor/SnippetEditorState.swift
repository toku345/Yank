import Foundation
import SwiftData

enum DirtyDraftDecision {
    case save
    case discard
    case cancel
}

struct SnippetDraft: Equatable {
    enum Kind: Equatable {
        case new(folderID: PersistentIdentifier, previousSnippetID: PersistentIdentifier?)
        case existing(snippetID: PersistentIdentifier, folderID: PersistentIdentifier)
    }

    let kind: Kind
    let originalTitle: String
    let originalContent: String
    var title: String
    var content: String

    var isDirty: Bool {
        switch kind {
        case .new:
            true
        case .existing:
            title != originalTitle || content != originalContent
        }
    }
}

struct ClipyImportMutationResult {
    let selectedFolder: SnippetFolder?
    let selectedSnippet: Snippet?

    var selectedFolderID: PersistentIdentifier? {
        selectedFolder?.persistentModelID
    }

    var selectedSnippetID: PersistentIdentifier? {
        selectedSnippet?.persistentModelID
    }
}

@Observable
@MainActor
final class SnippetEditorState {
    typealias DecisionProvider = @MainActor () -> DirtyDraftDecision

    var selectedFolderID: PersistentIdentifier?
    var selectedSnippetID: PersistentIdentifier?
    var draft: SnippetDraft?

    var hasDirtyDraft: Bool {
        draft?.isDirty == true
    }

    func selectFolder(_ folder: SnippetFolder) {
        selectedFolderID = folder.persistentModelID
        if let firstSnippet = SnippetOrdering.snippets(folder.snippets).first {
            selectSnippet(firstSnippet)
        } else {
            selectedSnippetID = nil
            draft = nil
        }
    }

    func selectSnippet(_ snippet: Snippet) {
        guard let folder = snippet.folder else { return }
        selectedFolderID = folder.persistentModelID
        selectedSnippetID = snippet.persistentModelID
        draft = SnippetDraft(
            kind: .existing(
                snippetID: snippet.persistentModelID,
                folderID: folder.persistentModelID
            ),
            originalTitle: snippet.title,
            originalContent: snippet.content,
            title: snippet.title,
            content: snippet.content
        )
    }

    func beginNewSnippet(in folder: SnippetFolder) {
        let folderID = folder.persistentModelID
        let previousSnippetID = selectedFolderID == folderID ? selectedSnippetID : nil
        selectedFolderID = folderID
        selectedSnippetID = nil
        draft = SnippetDraft(
            kind: .new(folderID: folderID, previousSnippetID: previousSnippetID),
            originalTitle: "",
            originalContent: "",
            title: "",
            content: ""
        )
    }

    func saveDraft(
        in context: ModelContext,
        saveChanges: SnippetMutations.SaveChanges = { try $0.save() }
    ) throws {
        guard let draft else { return }
        switch draft.kind {
        case .new(let folderID, _):
            let result = try SnippetMutations.createSnippet(
                title: draft.title,
                content: draft.content,
                folderID: folderID,
                in: context,
                saveChanges: saveChanges
            )
            try apply(result, in: context)
        case .existing(let snippetID, let folderID):
            try SnippetMutations.updateSnippet(
                id: snippetID,
                title: draft.title,
                content: draft.content,
                in: context,
                saveChanges: saveChanges
            )
            let normalizedTitle = try SnippetMutations.normalizedTitle(draft.title)
            selectedFolderID = folderID
            selectedSnippetID = snippetID
            self.draft = SnippetDraft(
                kind: .existing(snippetID: snippetID, folderID: folderID),
                originalTitle: normalizedTitle,
                originalContent: draft.content,
                title: normalizedTitle,
                content: draft.content
            )
        }
    }

    func discardDraft(in context: ModelContext) throws {
        guard let draft else { return }
        switch draft.kind {
        case .new(let folderID, let previousSnippetID):
            selectedFolderID = folderID
            if let previousSnippetID,
               let snippet = try findSnippet(id: previousSnippetID, in: context) {
                selectSnippet(snippet)
            } else {
                selectedSnippetID = nil
                self.draft = nil
            }
        case .existing(let snippetID, let folderID):
            selectedFolderID = folderID
            selectedSnippetID = snippetID
            self.draft = SnippetDraft(
                kind: draft.kind,
                originalTitle: draft.originalTitle,
                originalContent: draft.originalContent,
                title: draft.originalTitle,
                content: draft.originalContent
            )
        }
    }

    @discardableResult
    func resolveDirtyDraft(
        decisionProvider: DecisionProvider,
        in context: ModelContext,
        saveChanges: SnippetMutations.SaveChanges = { try $0.save() }
    ) throws -> Bool {
        guard hasDirtyDraft else { return true }
        switch decisionProvider() {
        case .save:
            try saveDraft(in: context, saveChanges: saveChanges)
            return true
        case .discard:
            try discardDraft(in: context)
            return true
        case .cancel:
            return false
        }
    }

    func apply(_ result: SnippetMutationResult, in context: ModelContext) throws {
        selectedFolderID = result.selectedFolderID
        selectedSnippetID = result.selectedSnippetID
        draft = nil
        if let snippetID = result.selectedSnippetID,
           let snippet = try findSnippet(id: snippetID, in: context) {
            selectSnippet(snippet)
        }
    }

    func apply(_ result: ClipyImportMutationResult) {
        guard let folder = result.selectedFolder else { return }
        if let snippet = result.selectedSnippet {
            selectSnippet(snippet)
        } else {
            selectFolder(folder)
        }
    }

    func synchronize(with folders: [SnippetFolder]) {
        let orderedFolders = SnippetOrdering.folders(folders)
        guard let folder = selectedFolderID.flatMap({ selectedID in
            orderedFolders.first { $0.persistentModelID == selectedID }
        }) ?? orderedFolders.first else {
            selectedFolderID = nil
            selectedSnippetID = nil
            draft = nil
            return
        }

        selectedFolderID = folder.persistentModelID
        let snippets = SnippetOrdering.snippets(folder.snippets)
        if let selectedSnippetID,
           let snippet = snippets.first(where: { $0.persistentModelID == selectedSnippetID }) {
            if draft == nil {
                selectSnippet(snippet)
            }
            return
        }

        if let draft,
           case .new(let folderID, _) = draft.kind,
           folderID == folder.persistentModelID {
            selectedSnippetID = nil
            return
        }

        if let snippet = snippets.first {
            selectSnippet(snippet)
        } else {
            selectedSnippetID = nil
            draft = nil
        }
    }

    private func findSnippet(
        id: PersistentIdentifier,
        in context: ModelContext
    ) throws -> Snippet? {
        try context.fetch(FetchDescriptor<Snippet>()).first {
            $0.persistentModelID == id
        }
    }
}
