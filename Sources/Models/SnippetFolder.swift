import SwiftData

@Model
final class SnippetFolder {
    var title: String
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder)
    var snippets: [Snippet] = []

    init(title: String, sortOrder: Int) {
        self.title = title
        self.sortOrder = sortOrder
    }
}
