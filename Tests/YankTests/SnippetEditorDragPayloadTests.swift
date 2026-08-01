import Foundation
import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetEditorDragPayloadTests: XCTestCase {
    func testPayloadCodableRoundTripPreservesKindAndIdentifier() throws {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        context.insert(folder)
        try context.save()
        let payload = SnippetEditorDragPayload(kind: .folder, id: folder.persistentModelID)

        let decoded = try JSONDecoder().decode(
            SnippetEditorDragPayload.self,
            from: JSONEncoder().encode(payload)
        )

        XCTAssertEqual(decoded.kind, .folder)
        XCTAssertEqual(decoded.id, folder.persistentModelID)
    }
}
