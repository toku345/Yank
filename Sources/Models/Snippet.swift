import Foundation
import SwiftData

@Model
final class Snippet {
    var title: String
    var content: String
    var index: Int
    var folder: SnippetFolder?

    init(title: String, content: String, index: Int, folder: SnippetFolder? = nil) {
        self.title = title
        self.content = content
        self.index = index
        self.folder = folder
    }
}
