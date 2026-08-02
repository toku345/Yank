import SwiftUI

@main
struct YankApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Yank", systemImage: "clipboard") {
            Button("Manage Snippets…") {
                appDelegate.coordinator.showSnippetEditor()
            }
            Divider()
            Button("About Yank") {
                NSApplication.shared.orderFrontStandardAboutPanel()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            Text("Yank Settings")
                .frame(width: 300, height: 200)
        }
    }
}
