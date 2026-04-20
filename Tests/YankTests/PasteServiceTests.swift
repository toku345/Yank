import XCTest
import AppKit
import SwiftData
@testable import Yank

final class PasteServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipItem.self, configurations: config)
    }

    func testWritePlainText_withStringValue_writesStringOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = ClipItem(
            title: "Rich text",
            primaryType: "public.html",
            availableTypes: ["public.html", "public.utf8-plain-text"],
            stringValue: "Hello, world!",
            htmlData: Data("<p>Hello, world!</p>".utf8)
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item)

        XCTAssertTrue(result)
        let pasteboard = NSPasteboard.general
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello, world!")
        // HTML type must not be present
        XCTAssertNil(pasteboard.data(forType: .html))
    }

    func testWritePlainText_withFileURLsOnly_writesPathString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = ClipItem(
            title: "[File: test.txt]",
            primaryType: "public.file-url",
            availableTypes: ["public.file-url"],
            fileURLs: ["file:///Users/test/test.txt"]
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item)

        XCTAssertTrue(result)
        let pasteboard = NSPasteboard.general
        XCTAssertEqual(pasteboard.string(forType: .string), "/Users/test/test.txt")
    }

    func testWritePlainText_withNoTextRepresentation_returnsFalse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = ClipItem(
            title: "[Image]",
            primaryType: "public.tiff",
            availableTypes: ["public.tiff"],
            imageData: Data([0xFF, 0xD8])
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item)

        XCTAssertFalse(result)
    }
}
