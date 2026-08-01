import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let yankSnippetEditorItem = UTType(
        exportedAs: "com.toku345.Yank.snippet-editor-item",
        conformingTo: .data
    )
}

struct SnippetEditorDragItem: Hashable {
    enum Kind: Hashable {
        case folder
        case snippet
    }

    let kind: Kind
    let id: PersistentIdentifier
}

struct SnippetEditorDragPayload: Codable, Transferable {
    let token: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .yankSnippetEditorItem)
    }
}

@MainActor
final class SnippetEditorDragRegistry {
    private var payloadByItem: [SnippetEditorDragItem: SnippetEditorDragPayload] = [:]
    private var itemByToken: [UUID: SnippetEditorDragItem] = [:]

    func payload(for item: SnippetEditorDragItem) -> SnippetEditorDragPayload {
        if let payload = payloadByItem[item] {
            return payload
        }
        let payload = SnippetEditorDragPayload(token: UUID())
        payloadByItem[item] = payload
        itemByToken[payload.token] = item
        return payload
    }

    func resolve(_ payload: SnippetEditorDragPayload) -> SnippetEditorDragItem? {
        itemByToken[payload.token]
    }
}
