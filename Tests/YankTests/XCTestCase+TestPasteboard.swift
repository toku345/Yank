import XCTest
import AppKit

extension XCTestCase {
    /// Creates a uniquely-named, isolated `NSPasteboard` for a test and registers
    /// teardown to clear and release it. Keeps tests off the real `.general`
    /// pasteboard so they never clobber the developer's clipboard or interfere
    /// with one another (issue #20).
    func makeTestPasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("com.toku345.Yank.tests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        addTeardownBlock {
            pasteboard.clearContents()
            pasteboard.releaseGlobally()
        }
        return pasteboard
    }
}
