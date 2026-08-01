import CoreTransferable
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let yankSnippetEditorItem = UTType(
        exportedAs: "com.toku345.Yank.snippet-editor-item",
        conformingTo: .data
    )
}

struct SnippetEditorDragPayload: Codable, Transferable {
    enum Kind: String, Codable {
        case folder
        case snippet
    }

    let kind: Kind
    let id: PersistentIdentifier

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .yankSnippetEditorItem)
    }
}
