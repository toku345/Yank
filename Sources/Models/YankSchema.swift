import SwiftData

enum YankSchema {
    static var current: Schema {
        Schema([ClipItem.self, SnippetFolder.self, Snippet.self])
    }
}
