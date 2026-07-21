import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Yank

final class SnippetSchemaMigrationTests: XCTestCase {
    func testAddingSnippetModelsPreservesExistingClipItems() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YankSnippetMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Yank.store")
        try createLegacyStore(at: storeURL)

        try autoreleasepool {
            let context = ModelContext(try openCurrentStore(at: storeURL))

            let clip = try XCTUnwrap(context.fetch(FetchDescriptor<ClipItem>()).first)
            XCTAssertEqual(clip.title, "Existing clip")
            XCTAssertEqual(clip.stringValue, "preserve me")

            let folder = SnippetFolder(title: "Migrated", sortOrder: 0)
            context.insert(folder)
            context.insert(Snippet(title: "New snippet", content: "new", sortOrder: 0, folder: folder))
            try context.save()
        }

        let reopenedContext = ModelContext(try openCurrentStore(at: storeURL))
        XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<ClipItem>()), 1)
        XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<SnippetFolder>()), 1)
        XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<Snippet>()), 1)
    }

    private func openCurrentStore(at storeURL: URL) throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration("Yank", schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func createLegacyStore(at storeURL: URL) throws {
        try autoreleasepool {
            let schema = Schema([ClipItem.self])
            let config = ModelConfiguration("Yank", schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            context.insert(ClipItem(
                title: "Existing clip",
                primaryType: UTType.utf8PlainText.identifier,
                availableTypes: [UTType.utf8PlainText.identifier],
                stringValue: "preserve me"
            ))
            try context.save()
        }
    }
}
