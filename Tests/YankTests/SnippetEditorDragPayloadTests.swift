import Foundation
import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetEditorDragPayloadTests: XCTestCase {
    func testPayloadCodableRoundTripResolvesOriginalItem() throws {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        context.insert(folder)
        try context.save()
        let registry = SnippetEditorDragRegistry()
        let item = SnippetEditorDragItem(kind: .folder, id: folder.persistentModelID)
        let payload = registry.payload(for: item)

        let decoded = try JSONDecoder().decode(
            SnippetEditorDragPayload.self,
            from: JSONEncoder().encode(payload)
        )

        XCTAssertEqual(decoded.token, payload.token)
        XCTAssertEqual(registry.resolve(decoded), item)
    }

    func testRegistryReusesPayloadForSameItem() throws {
        let (container, folder) = try makeFolder()
        withExtendedLifetime(container) {
            let registry = SnippetEditorDragRegistry()
            let item = SnippetEditorDragItem(kind: .folder, id: folder.persistentModelID)

            XCTAssertEqual(registry.payload(for: item).token, registry.payload(for: item).token)
        }
    }

    func testRegistryUsesDifferentTokensForDifferentItems() throws {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let first = SnippetFolder(title: "First", sortOrder: 0)
        let second = SnippetFolder(title: "Second", sortOrder: 1)
        context.insert(first)
        context.insert(second)
        try context.save()
        let registry = SnippetEditorDragRegistry()

        let firstPayload = registry.payload(for: SnippetEditorDragItem(kind: .folder, id: first.persistentModelID))
        let secondPayload = registry.payload(for: SnippetEditorDragItem(kind: .folder, id: second.persistentModelID))

        XCTAssertNotEqual(firstPayload.token, secondPayload.token)
    }

    func testRegistryRejectsUnknownToken() {
        let registry = SnippetEditorDragRegistry()

        XCTAssertNil(registry.resolve(SnippetEditorDragPayload(token: UUID())))
    }

    private func makeFolder() throws -> (ModelContainer, SnippetFolder) {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        context.insert(folder)
        try context.save()
        return (container, folder)
    }
}
