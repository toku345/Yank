import SwiftUI

@main
struct YankApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Yank", systemImage: "clipboard") {
            Button("About Yank") {
                NSApplication.shared.orderFrontStandardAboutPanel()
            }
            Divider()
            Button("Quit") {
                appDelegate.shutdown()
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
