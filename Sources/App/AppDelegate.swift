import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest the app runs only as a test host: skip real coordinator
        // startup (clipboard monitor / global hotkeys) so tests stay hermetic and
        // don't touch the on-disk Yank.store. Load-bearing — do not remove.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}
