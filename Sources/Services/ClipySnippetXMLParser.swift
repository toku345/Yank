import Foundation

struct ClipyImportedSnippet: Equatable {
    var title: String
    var content: String
}

struct ClipyImportedFolder: Equatable {
    var title: String
    var snippets: [ClipyImportedSnippet]
}

enum ClipySnippetXMLParserError: LocalizedError, Equatable {
    case invalidXML
    case unexpectedRoot
    case unexpectedElement(path: String)
    case unexpectedText(path: String)
    case duplicateElement(path: String)

    var errorDescription: String? {
        switch self {
        case .invalidXML:
            "The selected file is not valid XML."
        case .unexpectedRoot:
            "The XML root element must be <folders>."
        case .unexpectedElement(let path):
            "Unexpected element at \(path)."
        case .unexpectedText(let path):
            "Unexpected text at \(path)."
        case .duplicateElement(let path):
            "Duplicate element at \(path)."
        }
    }
}

enum ClipySnippetXMLParser {
    static func parse(data: Data) throws -> [ClipyImportedFolder] {
        let handler = Handler()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = handler
        guard parser.parse() else {
            throw handler.parserError ?? ClipySnippetXMLParserError.invalidXML
        }
        if let parserError = handler.parserError {
            throw parserError
        }
        guard let folders = handler.folders else {
            throw ClipySnippetXMLParserError.invalidXML
        }
        return folders
    }
}

// MARK: - XMLParser delegate

private final class Handler: NSObject, XMLParserDelegate {
    private enum State {
        case awaitingRoot
        case inFolders
        case inFolder
        case inFolderTitle
        case inSnippets
        case inSnippet
        case inSnippetTitle
        case inSnippetContent
        case finished
    }

    private var state: State = .awaitingRoot
    private var accumulatedFolders: [ClipyImportedFolder] = []
    private var folderTitle: String?
    private var folderHasTitle = false
    private var folderHasSnippets = false
    private var folderSnippets: [ClipyImportedSnippet] = []
    private var snippetTitle: String?
    private var snippetContent: String?
    private var snippetHasTitle = false
    private var snippetHasContent = false
    private var textBuffer = ""

    private(set) var folders: [ClipyImportedFolder]?
    private(set) var parserError: ClipySnippetXMLParserError?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard parserError == nil else { return }
        switch state {
        case .awaitingRoot:
            guard elementName == "folders" else {
                fail(.unexpectedRoot, parser: parser)
                return
            }
            state = .inFolders
        case .inFolders:
            guard elementName == "folder" else {
                fail(.unexpectedElement(path: "folders/\(elementName)"), parser: parser)
                return
            }
            beginFolder()
            state = .inFolder
        case .inFolder:
            startFolderChild(elementName, parser: parser)
        case .inSnippets:
            guard elementName == "snippet" else {
                fail(.unexpectedElement(path: "folders/folder/snippets/\(elementName)"), parser: parser)
                return
            }
            beginSnippet()
            state = .inSnippet
        case .inSnippet:
            startSnippetChild(elementName, parser: parser)
        case .inFolderTitle, .inSnippetTitle, .inSnippetContent, .finished:
            fail(.unexpectedElement(path: unexpectedChildPath(elementName)), parser: parser)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard parserError == nil else { return }
        switch state {
        case .inFolders:
            endFolders(elementName, parser: parser)
        case .inFolder:
            endFolder(elementName, parser: parser)
        case .inFolderTitle:
            endFolderTitle(elementName, parser: parser)
        case .inSnippets:
            endSnippets(elementName, parser: parser)
        case .inSnippet:
            endSnippet(elementName, parser: parser)
        case .inSnippetTitle:
            endSnippetTitle(elementName, parser: parser)
        case .inSnippetContent:
            endSnippetContent(elementName, parser: parser)
        case .awaitingRoot, .finished:
            fail(.invalidXML, parser: parser)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard parserError == nil else { return }
        appendText(string, parser: parser)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard parserError == nil else { return }
        guard let text = String(data: CDATABlock, encoding: .utf8) else {
            fail(.invalidXML, parser: parser)
            return
        }
        appendText(text, parser: parser)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if parserError == nil {
            parserError = .invalidXML
        }
    }

    // MARK: - Element end handlers

    private func endFolders(_ elementName: String, parser: XMLParser) {
        guard elementName == "folders" else {
            fail(.invalidXML, parser: parser)
            return
        }
        folders = accumulatedFolders
        state = .finished
    }

    private func endFolder(_ elementName: String, parser: XMLParser) {
        guard elementName == "folder" else {
            fail(.invalidXML, parser: parser)
            return
        }
        finishFolder()
        state = .inFolders
    }

    private func endFolderTitle(_ elementName: String, parser: XMLParser) {
        guard elementName == "title" else {
            fail(.invalidXML, parser: parser)
            return
        }
        folderTitle = textBuffer
        textBuffer = ""
        state = .inFolder
    }

    private func endSnippets(_ elementName: String, parser: XMLParser) {
        guard elementName == "snippets" else {
            fail(.invalidXML, parser: parser)
            return
        }
        state = .inFolder
    }

    private func endSnippet(_ elementName: String, parser: XMLParser) {
        guard elementName == "snippet" else {
            fail(.invalidXML, parser: parser)
            return
        }
        finishSnippet()
        state = .inSnippets
    }

    private func endSnippetTitle(_ elementName: String, parser: XMLParser) {
        guard elementName == "title" else {
            fail(.invalidXML, parser: parser)
            return
        }
        snippetTitle = textBuffer
        textBuffer = ""
        state = .inSnippet
    }

    private func endSnippetContent(_ elementName: String, parser: XMLParser) {
        guard elementName == "content" else {
            fail(.invalidXML, parser: parser)
            return
        }
        snippetContent = textBuffer
        textBuffer = ""
        state = .inSnippet
    }
}

private extension Handler {
    // MARK: - Helpers

    private func beginFolder() {
        folderTitle = nil
        folderHasTitle = false
        folderHasSnippets = false
        folderSnippets = []
    }

    private func finishFolder() {
        accumulatedFolders.append(
            ClipyImportedFolder(
                title: folderTitle ?? "",
                snippets: folderHasSnippets ? folderSnippets : []
            )
        )
    }

    private func beginSnippet() {
        snippetTitle = nil
        snippetContent = nil
        snippetHasTitle = false
        snippetHasContent = false
    }

    private func finishSnippet() {
        folderSnippets.append(
            ClipyImportedSnippet(
                title: snippetTitle ?? "",
                content: snippetContent ?? ""
            )
        )
    }

    private func startFolderChild(_ elementName: String, parser: XMLParser) {
        switch elementName {
        case "title":
            guard !folderHasTitle else {
                fail(.duplicateElement(path: "folders/folder/title"), parser: parser)
                return
            }
            folderHasTitle = true
            textBuffer = ""
            state = .inFolderTitle
        case "snippets":
            guard !folderHasSnippets else {
                fail(.duplicateElement(path: "folders/folder/snippets"), parser: parser)
                return
            }
            folderHasSnippets = true
            folderSnippets = []
            state = .inSnippets
        default:
            fail(.unexpectedElement(path: "folders/folder/\(elementName)"), parser: parser)
        }
    }

    private func startSnippetChild(_ elementName: String, parser: XMLParser) {
        switch elementName {
        case "title":
            guard !snippetHasTitle else {
                fail(.duplicateElement(path: "folders/folder/snippets/snippet/title"), parser: parser)
                return
            }
            snippetHasTitle = true
            textBuffer = ""
            state = .inSnippetTitle
        case "content":
            guard !snippetHasContent else {
                fail(.duplicateElement(path: "folders/folder/snippets/snippet/content"), parser: parser)
                return
            }
            snippetHasContent = true
            textBuffer = ""
            state = .inSnippetContent
        default:
            fail(
                .unexpectedElement(path: "folders/folder/snippets/snippet/\(elementName)"),
                parser: parser
            )
        }
    }

    private func appendText(_ string: String, parser: XMLParser) {
        switch state {
        case .inFolderTitle, .inSnippetTitle, .inSnippetContent:
            textBuffer += string
        default:
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            fail(.unexpectedText(path: currentPath), parser: parser)
        }
    }

    private var currentPath: String {
        switch state {
        case .awaitingRoot, .finished:
            "/"
        case .inFolders:
            "folders"
        case .inFolder:
            "folders/folder"
        case .inFolderTitle:
            "folders/folder/title"
        case .inSnippets:
            "folders/folder/snippets"
        case .inSnippet:
            "folders/folder/snippets/snippet"
        case .inSnippetTitle:
            "folders/folder/snippets/snippet/title"
        case .inSnippetContent:
            "folders/folder/snippets/snippet/content"
        }
    }

    private func unexpectedChildPath(_ elementName: String) -> String {
        switch state {
        case .inFolderTitle:
            "folders/folder/title/\(elementName)"
        case .inSnippetTitle:
            "folders/folder/snippets/snippet/title/\(elementName)"
        case .inSnippetContent:
            "folders/folder/snippets/snippet/content/\(elementName)"
        case .finished:
            elementName
        default:
            elementName
        }
    }

    private func fail(_ error: ClipySnippetXMLParserError, parser: XMLParser) {
        parserError = error
        parser.abortParsing()
    }}
