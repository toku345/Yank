import SwiftData

enum YankSchema {
    /// Single source of truth for the persisted schema; every @Model must be
    /// registered here (consumed by AppCoordinator and the migration tests).
    /// See ADR 0010.
    static var current: Schema {
        Schema([ClipItem.self, SnippetFolder.self, Snippet.self])
    }
}
