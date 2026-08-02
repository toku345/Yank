import SwiftData

struct SnippetCollectionSnapshot: Equatable {
    let folderID: PersistentIdentifier
    let title: String
    let sortOrder: Int
    let snippetIDs: [PersistentIdentifier]
}

enum SnippetOrdering {
    static func folders(_ folders: [SnippetFolder]) -> [SnippetFolder] {
        folders.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.persistentModelID < $1.persistentModelID
        }
    }

    static func snippets(_ snippets: [Snippet]) -> [Snippet] {
        snippets.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.persistentModelID < $1.persistentModelID
        }
    }
}

enum SnippetCollectionProjection {
    static func snapshots(from folders: [SnippetFolder]) -> [SnippetCollectionSnapshot] {
        SnippetOrdering.folders(folders).map { folder in
            SnippetCollectionSnapshot(
                folderID: folder.persistentModelID,
                title: folder.title,
                sortOrder: folder.sortOrder,
                snippetIDs: SnippetOrdering.snippets(folder.snippets).map(\.persistentModelID)
            )
        }
    }

    static func selectableSnippetIDs(
        from snapshots: [SnippetCollectionSnapshot]
    ) -> [PersistentIdentifier] {
        snapshots.flatMap(\.snippetIDs)
    }
}
