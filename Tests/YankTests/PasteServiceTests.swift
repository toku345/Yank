import XCTest
import AppKit
import SwiftData
@testable import Yank

final class PasteServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipItem.self, configurations: config)
    }

    func testWriteToPasteboard_withStringValue_writesString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pasteboard = makeTestPasteboard()

        let item = ClipItem(
            title: "Plain",
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"],
            stringValue: "Hello, original!"
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writeToPasteboard(item: item, pasteboard: pasteboard)

        XCTAssertTrue(result)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello, original!")
    }

    func testWritePlainText_withStringValue_writesStringOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pasteboard = makeTestPasteboard()

        let item = ClipItem(
            title: "Rich text",
            primaryType: "public.html",
            availableTypes: ["public.html", "public.utf8-plain-text"],
            stringValue: "Hello, world!",
            htmlData: Data("<p>Hello, world!</p>".utf8)
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item, pasteboard: pasteboard)

        XCTAssertTrue(result)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello, world!")
        // HTML type must not be present
        XCTAssertNil(pasteboard.data(forType: .html))
    }

    func testWritePlainText_withFileURLsOnly_writesPathString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pasteboard = makeTestPasteboard()

        let item = ClipItem(
            title: "[File: test.txt]",
            primaryType: "public.file-url",
            availableTypes: ["public.file-url"],
            fileURLs: ["file:///Users/test/test.txt"]
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item, pasteboard: pasteboard)

        XCTAssertTrue(result)
        XCTAssertEqual(pasteboard.string(forType: .string), "/Users/test/test.txt")
    }

    func testWritePlainText_withNoTextRepresentation_returnsFalse() throws {
        // Seed a sentinel so we can verify the clipboard is not wiped on failure.
        let pasteboard = makeTestPasteboard()
        let sentinel = NSPasteboardItem()
        sentinel.setString("sentinel", forType: .string)
        pasteboard.writeObjects([sentinel])

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

        let result = PasteService.writePlainTextToPasteboard(item: item, pasteboard: pasteboard)

        XCTAssertFalse(result)
        XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
    }

    func testWritePlainText_withHTMLOnly_extractsPlainText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pasteboard = makeTestPasteboard()

        let html = "<p>Hello, <b>world</b>!</p>"
        let item = ClipItem(
            title: "[HTML]",
            primaryType: "public.html",
            availableTypes: ["public.html"],
            htmlData: Data(html.utf8)
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item, pasteboard: pasteboard)

        XCTAssertTrue(result)
        let written = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(written.contains("Hello"))
        XCTAssertTrue(written.contains("world"))
        XCTAssertFalse(written.contains("<"))
        XCTAssertNil(pasteboard.data(forType: .html))
    }

    func testWritePlainText_withRTFOnly_extractsPlainText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pasteboard = makeTestPasteboard()

        let rtf = "{\\rtf1\\ansi Hello RTF}"
        let item = ClipItem(
            title: "[RTF]",
            primaryType: "public.rtf",
            availableTypes: ["public.rtf"],
            rtfData: Data(rtf.utf8)
        )
        context.insert(item)
        try context.save()

        let result = PasteService.writePlainTextToPasteboard(item: item, pasteboard: pasteboard)

        XCTAssertTrue(result)
        XCTAssertTrue((pasteboard.string(forType: .string) ?? "").contains("Hello RTF"))
        XCTAssertNil(pasteboard.data(forType: .rtf))
    }
}
