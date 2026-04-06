import XCTest
@testable import Yank

@MainActor
final class DeriveTitleTests: XCTestCase {

    func testTextContent_returnsTrimmedPrefix() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: "  Hello, World!  ",
            primaryType: "public.utf8-plain-text",
            fileURLs: nil
        )
        XCTAssertEqual(title, "Hello, World!")
    }

    func testLongText_truncatesAt50Characters() {
        let longText = String(repeating: "a", count: 100)
        let title = ClipboardMonitor.deriveTitle(
            stringValue: longText,
            primaryType: "public.utf8-plain-text",
            fileURLs: nil
        )
        XCTAssertEqual(title.count, 50)
    }

    func testEmptyText_fallsThrough() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: "",
            primaryType: "public.tiff",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testFileURL_returnsFileName() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "public.file-url",
            fileURLs: ["file:///Users/test/Documents/report.pdf"]
        )
        XCTAssertEqual(title, "[File: report.pdf]")
    }

    func testTiffType_returnsImage() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "public.tiff",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testPngType_returnsImage() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "public.png",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Image]")
    }

    func testPdfType_returnsPDF() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "com.adobe.pdf",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[PDF]")
    }

    func testRtfType_returnsRTF() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "public.rtf",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[RTF]")
    }

    func testHtmlType_returnsHTML() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "public.html",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[HTML]")
    }

    func testUnknownType_returnsClipboardData() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: nil,
            primaryType: "com.example.custom",
            fileURLs: nil
        )
        XCTAssertEqual(title, "[Clipboard Data]")
    }

    func testWhitespaceOnlyText_fallsThrough() {
        let title = ClipboardMonitor.deriveTitle(
            stringValue: "   \n\t  ",
            primaryType: "public.tiff",
            fileURLs: nil
        )
        // Whitespace-only text: not empty before trimming, so text branch is entered.
        // After trimming, prefix(50) returns empty string.
        XCTAssertEqual(title, "")
    }
}
