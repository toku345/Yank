import XCTest
@testable import Yank

@MainActor
final class DeriveTitleTests: XCTestCase {

    func testTextContent_returnsTrimmedPrefix() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: "  Hello, World!  ",
            availableTypes: ["public.utf8-plain-text"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "Hello, World!")
    }

    func testLongText_truncatesAt50Characters() {
        let longText = String(repeating: "a", count: 100)
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: longText,
            availableTypes: ["public.utf8-plain-text"],
            fileURLs: nil
        )
        XCTAssertEqual(title.count, 50)
    }

    func testEmptyText_fallsThrough() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: "",
            availableTypes: ["public.tiff"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testFileURL_returnsFileName() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["public.file-url"],
            fileURLs: ["file:///Users/test/Documents/report.pdf"]
        )
        XCTAssertEqual(title, "[File: report.pdf]")
    }

    func testTiffType_returnsImage() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["public.tiff"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testPngType_returnsImage() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["public.png"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testPngType_withUnknownLeadingType_returnsImage() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["com.apple.unknown-internal-type", "public.png", "public.tiff"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testPdfType_returnsPDF() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["com.adobe.pdf"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[PDF]")
    }

    func testRtfType_returnsRTF() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["public.rtf"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[RTF]")
    }

    func testHtmlType_returnsHTML() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["public.html"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[HTML]")
    }

    func testUnknownType_returnsClipboardData() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: nil,
            availableTypes: ["com.example.custom"],
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Clipboard Data]")
    }

    func testWhitespaceOnlyText_fallsThrough() {
        let title = ClipboardHistoryWriter.deriveTitle(
            stringValue: "   \n\t  ",
            availableTypes: ["public.tiff"],
            fileURLs: nil
        )
        // Whitespace-only text falls through to type-based title
        XCTAssertEqual(title, "[Image]")
    }
}
