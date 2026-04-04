import Foundation
import SwiftData

@Model
final class SnippetFolder {
    var title: String
    var index: Int
    @Relationship(deleteRule: .cascade, inverse: \Snippet.folder)
    var snippets: [Snippet]

    init(title: String, index: Int, snippets: [Snippet] = []) {
        self.title = title
        self.index = index
        self.snippets = snippets
    }
}
