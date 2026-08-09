import XCTest
@testable import Yank

final class ClipySnippetXMLParserTests: XCTestCase {
    func testParsesExporterShapedDocumentPreservingOrder() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <folders>
          <folder>
            <title>Folder A</title>
            <snippets>
              <snippet>
                <title>Snippet 1</title>
                <content>hello</content>
              </snippet>
              <snippet>
                <title>Snippet 2</title>
                <content>world</content>
              </snippet>
            </snippets>
          </folder>
          <folder>
            <snippets>
              <snippet>
                <content>only content</content>
                <title>Snippet 3</title>
              </snippet>
            </snippets>
            <title>Folder B</title>
          </folder>
        </folders>
        """

        let folders = try ClipySnippetXMLParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(folders, [
            ClipyImportedFolder(
                title: "Folder A",
                snippets: [
                    ClipyImportedSnippet(title: "Snippet 1", content: "hello"),
                    ClipyImportedSnippet(title: "Snippet 2", content: "world")
                ]
            ),
            ClipyImportedFolder(
                title: "Folder B",
                snippets: [
                    ClipyImportedSnippet(title: "Snippet 3", content: "only content")
                ]
            )
        ])
    }

    func testParsesEmptyFoldersAsSuccess() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <folders/>
        """
        let folders = try ClipySnippetXMLParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(folders, [])
    }

    func testPreservesContentWhitespaceAndMissingTitlesAsEmptyRaw() throws {
        let trailingNewline = "\n"
        let xml = """
        <folders>
          <folder>
            <snippets>
              <snippet>
                <content>  padded\(trailingNewline)</content>
              </snippet>
              <snippet>
                <title>   </title>
                <content></content>
              </snippet>
            </snippets>
          </folder>
          <folder>
            <title></title>
          </folder>
        </folders>
        """

        let folders = try ClipySnippetXMLParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(folders[0].title, "")
        XCTAssertEqual(folders[0].snippets.count, 2)
        XCTAssertEqual(folders[0].snippets[0].title, "")
        XCTAssertEqual(folders[0].snippets[0].content, "  padded\n")
        XCTAssertEqual(folders[0].snippets[1].title, "   ")
        XCTAssertEqual(folders[0].snippets[1].content, "")
        XCTAssertEqual(folders[1].title, "")
        XCTAssertEqual(folders[1].snippets, [])
    }

    func testParsesCDATAAndEscapedEntitiesInContent() throws {
        let xml = """
        <folders>
          <folder>
            <snippets>
              <snippet>
                <content><![CDATA[if a < b && c > d]]>&amp; done</content>
              </snippet>
            </snippets>
          </folder>
        </folders>
        """

        let folders = try ClipySnippetXMLParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(folders[0].snippets[0].content, "if a < b && c > d& done")
    }

    func testRejectsMalformedXML() {
        assertParseFails("<folders><folder>", expected: .invalidXML)
    }

    func testRejectsUnexpectedRoot() {
        assertParseFails("<snippets></snippets>", expected: .unexpectedRoot)
    }

    func testRejectsUnexpectedElementUnderFolders() {
        assertParseFails(
            "<folders><not-folder/></folders>",
            expected: .unexpectedElement(path: "folders/not-folder")
        )
    }

    func testRejectsUnexpectedElementUnderFolder() {
        assertParseFails(
            "<folders><folder><index>0</index></folder></folders>",
            expected: .unexpectedElement(path: "folders/folder/index")
        )
    }

    func testRejectsNonWhitespaceTextOutsideValueElements() {
        assertParseFails(
            "<folders><folder><snippets><snippet><title>A</title>lost body</snippet></snippets></folder></folders>",
            expected: .unexpectedText(path: "folders/folder/snippets/snippet")
        )
    }

    func testRejectsDuplicateFolderTitle() {
        assertParseFails(
            """
            <folders>
              <folder>
                <title>A</title>
                <title>B</title>
              </folder>
            </folders>
            """,
            expected: .duplicateElement(path: "folders/folder/title")
        )
    }

    func testRejectsDuplicateSnippetContent() {
        assertParseFails(
            """
            <folders>
              <folder>
                <snippets>
                  <snippet>
                    <content>one</content>
                    <content>two</content>
                  </snippet>
                </snippets>
              </folder>
            </folders>
            """,
            expected: .duplicateElement(path: "folders/folder/snippets/snippet/content")
        )
    }

    func testErrorDescriptionsAreUserFacing() {
        XCTAssertEqual(
            ClipySnippetXMLParserError.invalidXML.errorDescription,
            "The selected file is not valid XML."
        )
        XCTAssertEqual(
            ClipySnippetXMLParserError.unexpectedRoot.errorDescription,
            "The XML root element must be <folders>."
        )
        XCTAssertEqual(
            ClipySnippetXMLParserError.unexpectedElement(path: "folders/x").errorDescription,
            "Unexpected element at folders/x."
        )
        XCTAssertEqual(
            ClipySnippetXMLParserError.unexpectedText(path: "folders/folder").errorDescription,
            "Unexpected text at folders/folder."
        )
        XCTAssertEqual(
            ClipySnippetXMLParserError.duplicateElement(path: "folders/folder/title").errorDescription,
            "Duplicate element at folders/folder/title."
        )
    }

    private func assertParseFails(_ xml: String, expected: ClipySnippetXMLParserError) {
        XCTAssertThrowsError(try ClipySnippetXMLParser.parse(data: Data(xml.utf8))) { error in
            XCTAssertEqual(error as? ClipySnippetXMLParserError, expected)
        }
    }
}
