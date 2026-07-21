import SwiftData

@Model
final class Snippet {
    var title: String
    var content: String
    var sortOrder: Int
    // SwiftData clears the inverse before cascading a folder deletion, so the
    // persisted relationship must accept nil even though creation requires a folder.
    var folder: SnippetFolder?

    init(title: String, content: String, sortOrder: Int, folder: SnippetFolder) {
        self.title = title
        self.content = content
        self.sortOrder = sortOrder
        self.folder = folder
    }
}
