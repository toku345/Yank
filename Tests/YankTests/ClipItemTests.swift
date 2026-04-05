import XCTest
import SwiftData
@testable import Yank

final class ClipItemTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ClipItem.self, Snippet.self, SnippetFolder.self,
            configurations: config
        )
    }

    func testClipItemRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = ClipItem(
            title: "Hello",
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"],
            stringValue: "Hello, world!"
        )
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<ClipItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Hello")
        XCTAssertEqual(fetched.first?.stringValue, "Hello, world!")
        XCTAssertEqual(fetched.first?.primaryType, "public.utf8-plain-text")
        XCTAssertEqual(fetched.first?.isPinned, false)
        XCTAssertEqual(fetched.first?.isSensitive, false)
    }

    func testClipItemWithMultipleTypes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let rtfData = Data("rtf content".utf8)
        let item = ClipItem(
            title: "Rich text",
            primaryType: "public.rtf",
            availableTypes: ["public.rtf", "public.utf8-plain-text"],
            stringValue: "plain fallback",
            rtfData: rtfData
        )
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<ClipItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.availableTypes.count, 2)
        XCTAssertEqual(fetched.first?.rtfData, rtfData)
        XCTAssertEqual(fetched.first?.stringValue, "plain fallback")
    }

    func testSnippetFolderCascadeDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let folder = SnippetFolder(title: "My Snippets", index: 0)
        let snippet = Snippet(title: "greeting", content: "Hello!", index: 0, folder: folder)
        context.insert(folder)
        context.insert(snippet)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<SnippetFolder>())
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.snippets.count, 1)

        context.delete(folder)
        try context.save()

        let remainingSnippets = try context.fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(remainingSnippets.count, 0)
    }
}
