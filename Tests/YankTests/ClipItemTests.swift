import XCTest
import SwiftData
import UniformTypeIdentifiers
@testable import Yank

final class ClipItemTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipItem.self, configurations: config)
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
    }

    func testClipItemWithMultipleTypes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let rtfData = Data("rtf content".utf8)
        let htmlData = Data("<p>hello</p>".utf8)
        let item = ClipItem(
            title: "Rich text",
            primaryType: "public.rtf",
            availableTypes: ["public.rtf", "public.utf8-plain-text", "public.html"],
            stringValue: "plain fallback",
            rtfData: rtfData,
            htmlData: htmlData
        )
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<ClipItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.availableTypes.count, 3)
        XCTAssertEqual(fetched.first?.rtfData, rtfData)
        XCTAssertEqual(fetched.first?.htmlData, htmlData)
        XCTAssertEqual(fetched.first?.stringValue, "plain fallback")
    }

    func testImageDataRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tiffData = Data([0x49, 0x49, 0x2A, 0x00])
        let item = ClipItem(
            title: "[Image]",
            primaryType: "public.tiff",
            availableTypes: ["public.tiff"],
            imageData: tiffData
        )
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<ClipItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.imageData, tiffData)
        XCTAssertNil(fetched.first?.stringValue)
    }

    func testPrimaryUTType() {
        let item = ClipItem(
            title: "test",
            primaryType: "public.rtf",
            availableTypes: ["public.rtf"]
        )
        XCTAssertEqual(item.primaryUTType, UTType.rtf)

        let plainItem = ClipItem(
            title: "test",
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"]
        )
        XCTAssertEqual(plainItem.primaryUTType, UTType.utf8PlainText)
        XCTAssertTrue(plainItem.primaryUTType?.conforms(to: .plainText) ?? false)
    }

    func testPrimaryUTTypeWithInvalidIdentifier() {
        let item = ClipItem(
            title: "test",
            primaryType: "invalid.nonexistent.type",
            availableTypes: ["invalid.nonexistent.type"]
        )
        XCTAssertNil(item.primaryUTType)
    }
}
