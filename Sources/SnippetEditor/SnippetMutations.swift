import Foundation
import SwiftData

enum SnippetEditorMutationError: LocalizedError, Equatable {
    case contextHasPendingChanges
    case folderNotFound
    case snippetNotFound
    case invalidTitle
    case invalidMove

    var errorDescription: String? {
        switch self {
        case .contextHasPendingChanges:
            "The snippet store has pending changes. Try the operation again."
        case .folderNotFound:
            "The selected folder no longer exists."
        case .snippetNotFound:
            "The selected snippet no longer exists."
        case .invalidTitle:
            "Enter a title that contains at least one non-space character."
        case .invalidMove:
            "The requested move is no longer valid."
        }
    }
}

struct SnippetMutationResult: Equatable {
    let selectedFolderID: PersistentIdentifier?
    let selectedSnippetID: PersistentIdentifier?
}

@MainActor
enum SnippetMutations {
    typealias SaveChanges = (ModelContext) throws -> Void

    static func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SnippetEditorMutationError.invalidTitle
        }
        return normalized
    }

    static func loadFolders(in context: ModelContext) throws -> [SnippetFolder] {
        SnippetOrdering.folders(try context.fetch(FetchDescriptor<SnippetFolder>()))
    }

    static func loadSnippets(
        in folder: SnippetFolder,
        context: ModelContext
    ) throws -> [Snippet] {
        let folderID = folder.persistentModelID
        let snippets = try context.fetch(FetchDescriptor<Snippet>()).filter {
            $0.folder?.persistentModelID == folderID
        }
        return SnippetOrdering.snippets(snippets)
    }

    static func createFolder(
        title: String,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> SnippetMutationResult {
        try requireCleanContext(context)
        let folders = try loadFolders(in: context)
        let folder = SnippetFolder(
            title: try normalizedTitle(title),
            sortOrder: folders.count
        )
        context.insert(folder)
        try saveOrRollback(context, saveChanges: saveChanges)
        return SnippetMutationResult(
            selectedFolderID: folder.persistentModelID,
            selectedSnippetID: nil
        )
    }

    static func renameFolder(
        id: PersistentIdentifier,
        title: String,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws {
        try requireCleanContext(context)
        let folder = try findFolder(id: id, in: context)
        folder.title = try normalizedTitle(title)
        try saveOrRollback(context, saveChanges: saveChanges)
    }

    static func deleteFolder(
        id: PersistentIdentifier,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> SnippetMutationResult {
        try requireCleanContext(context)
        let folders = try loadFolders(in: context)
        guard let removedIndex = folders.firstIndex(where: { $0.persistentModelID == id }) else {
            throw SnippetEditorMutationError.folderNotFound
        }
        context.delete(folders[removedIndex])
        let remaining = folders.filter { $0.persistentModelID != id }
        normalizeFolders(remaining)
        try saveOrRollback(context, saveChanges: saveChanges)

        let selectedFolder = remaining.isEmpty ? nil : remaining[min(removedIndex, remaining.count - 1)]
        let selectedSnippet = selectedFolder.flatMap { SnippetOrdering.snippets($0.snippets).first }
        return SnippetMutationResult(
            selectedFolderID: selectedFolder?.persistentModelID,
            selectedSnippetID: selectedSnippet?.persistentModelID
        )
    }
}

extension SnippetMutations {
    @discardableResult
    static func moveFolder(
        id: PersistentIdentifier,
        before targetID: PersistentIdentifier?,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> Bool {
        try requireCleanContext(context)
        let original = try loadFolders(in: context)
        guard let sourceIndex = original.firstIndex(where: { $0.persistentModelID == id }) else {
            throw SnippetEditorMutationError.folderNotFound
        }
        guard targetID != id else { return false }

        var reordered = original
        let moved = reordered.remove(at: sourceIndex)
        if let targetID {
            guard let targetIndex = reordered.firstIndex(where: { $0.persistentModelID == targetID }) else {
                throw SnippetEditorMutationError.invalidMove
            }
            reordered.insert(moved, at: targetIndex)
        } else {
            reordered.append(moved)
        }
        guard reordered.map(\.persistentModelID) != original.map(\.persistentModelID) else {
            return false
        }
        normalizeFolders(reordered)
        try saveOrRollback(context, saveChanges: saveChanges)
        return true
    }
}

extension SnippetMutations {
    static func createSnippet(
        title: String,
        content: String,
        folderID: PersistentIdentifier,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> SnippetMutationResult {
        try requireCleanContext(context)
        let folder = try findFolder(id: folderID, in: context)
        let snippets = try loadSnippets(in: folder, context: context)
        let snippet = Snippet(
            title: try normalizedTitle(title),
            content: content,
            sortOrder: snippets.count,
            folder: folder
        )
        context.insert(snippet)
        try saveOrRollback(context, saveChanges: saveChanges)
        return SnippetMutationResult(
            selectedFolderID: folder.persistentModelID,
            selectedSnippetID: snippet.persistentModelID
        )
    }

    static func updateSnippet(
        id: PersistentIdentifier,
        title: String,
        content: String,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws {
        try requireCleanContext(context)
        let snippet = try findSnippet(id: id, in: context)
        snippet.title = try normalizedTitle(title)
        snippet.content = content
        try saveOrRollback(context, saveChanges: saveChanges)
    }

    static func deleteSnippet(
        id: PersistentIdentifier,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> SnippetMutationResult {
        try requireCleanContext(context)
        let snippet = try findSnippet(id: id, in: context)
        guard let folder = snippet.folder else {
            throw SnippetEditorMutationError.invalidMove
        }
        let snippets = try loadSnippets(in: folder, context: context)
        guard let removedIndex = snippets.firstIndex(where: { $0.persistentModelID == id }) else {
            throw SnippetEditorMutationError.snippetNotFound
        }
        context.delete(snippet)
        let remaining = snippets.filter { $0.persistentModelID != id }
        normalizeSnippets(remaining)
        try saveOrRollback(context, saveChanges: saveChanges)
        let selected = remaining.isEmpty ? nil : remaining[min(removedIndex, remaining.count - 1)]
        return SnippetMutationResult(
            selectedFolderID: folder.persistentModelID,
            selectedSnippetID: selected?.persistentModelID
        )
    }
}

extension SnippetMutations {
    static func moveSnippet(
        id: PersistentIdentifier,
        to destinationFolderID: PersistentIdentifier,
        before targetID: PersistentIdentifier?,
        in context: ModelContext,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> SnippetMutationResult? {
        try requireCleanContext(context)
        let snippet = try findSnippet(id: id, in: context)
        guard let sourceFolder = snippet.folder else {
            throw SnippetEditorMutationError.invalidMove
        }
        let destinationFolder = try findFolder(id: destinationFolderID, in: context)
        guard targetID != id else { return nil }

        if sourceFolder.persistentModelID == destinationFolderID {
            let original = try loadSnippets(in: sourceFolder, context: context)
            var reordered = original
            guard let sourceIndex = reordered.firstIndex(where: { $0.persistentModelID == id }) else {
                throw SnippetEditorMutationError.snippetNotFound
            }
            let moved = reordered.remove(at: sourceIndex)
            if let targetID {
                guard let targetIndex = reordered.firstIndex(where: { $0.persistentModelID == targetID }) else {
                    throw SnippetEditorMutationError.invalidMove
                }
                reordered.insert(moved, at: targetIndex)
            } else {
                reordered.append(moved)
            }
            guard reordered.map(\.persistentModelID) != original.map(\.persistentModelID) else {
                return nil
            }
            normalizeSnippets(reordered)
        } else {
            let sourceSnippets = try loadSnippets(in: sourceFolder, context: context)
                .filter { $0.persistentModelID != id }
            var destinationSnippets = try loadSnippets(in: destinationFolder, context: context)
            if let targetID {
                guard let targetIndex = destinationSnippets.firstIndex(where: {
                    $0.persistentModelID == targetID
                }) else {
                    throw SnippetEditorMutationError.invalidMove
                }
                destinationSnippets.insert(snippet, at: targetIndex)
            } else {
                destinationSnippets.append(snippet)
            }
            snippet.folder = destinationFolder
            normalizeSnippets(sourceSnippets)
            normalizeSnippets(destinationSnippets)
        }

        try saveOrRollback(context, saveChanges: saveChanges)
        return SnippetMutationResult(
            selectedFolderID: destinationFolderID,
            selectedSnippetID: id
        )
    }
}

private extension SnippetMutations {
    private static func requireCleanContext(_ context: ModelContext) throws {
        guard !context.hasChanges else {
            throw SnippetEditorMutationError.contextHasPendingChanges
        }
    }

    private static func findFolder(
        id: PersistentIdentifier,
        in context: ModelContext
    ) throws -> SnippetFolder {
        guard let folder = try context.fetch(FetchDescriptor<SnippetFolder>()).first(where: {
            $0.persistentModelID == id
        }) else {
            throw SnippetEditorMutationError.folderNotFound
        }
        return folder
    }

    private static func findSnippet(
        id: PersistentIdentifier,
        in context: ModelContext
    ) throws -> Snippet {
        guard let snippet = try context.fetch(FetchDescriptor<Snippet>()).first(where: {
            $0.persistentModelID == id
        }) else {
            throw SnippetEditorMutationError.snippetNotFound
        }
        return snippet
    }

    private static func normalizeFolders(_ folders: [SnippetFolder]) {
        for (index, folder) in folders.enumerated() {
            folder.sortOrder = index
        }
    }

    private static func normalizeSnippets(_ snippets: [Snippet]) {
        for (index, snippet) in snippets.enumerated() {
            snippet.sortOrder = index
        }
    }

    private static func saveOrRollback(
        _ context: ModelContext,
        saveChanges: SaveChanges
    ) throws {
        do {
            try saveChanges(context)
        } catch {
            let saveError = error
            context.rollback()
            _ = try context.fetch(FetchDescriptor<SnippetFolder>())
            _ = try context.fetch(FetchDescriptor<Snippet>())
            throw saveError
        }
    }
}
