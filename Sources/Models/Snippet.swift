import SwiftData

@Model
final class Snippet {
    var title: String
    var content: String
    var sortOrder: Int
    var folder: SnippetFolder

    init(title: String, content: String, sortOrder: Int, folder: SnippetFolder) {
        self.title = title
        self.content = content
        self.sortOrder = sortOrder
        self.folder = folder
    }
}
