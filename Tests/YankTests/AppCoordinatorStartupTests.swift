import AppKit
import XCTest
@testable import Yank

@MainActor
final class AppCoordinatorStartupTests: XCTestCase {
    private enum StartupError: Error {
        case migrationFailed
    }

    func testContainerFailurePresentsErrorThenTerminatesWithoutStartingServices() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YankStartupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = ["Yank.store", "Yank.store-wal", "Yank.store-shm", "Yank.store-journal"]
        for name in names {
            try Data("preserve \(name)".utf8).write(to: directory.appendingPathComponent(name))
        }

        var events: [String] = []
        var presentedAlert: NSAlert?
        let coordinator = AppCoordinator(
            createModelContainer: {
                events.append("create")
                throw StartupError.migrationFailed
            },
            presentStoreError: { alert in
                events.append("alert")
                presentedAlert = alert
            },
            terminate: { events.append("terminate") }
        )

        coordinator.start()

        XCTAssertEqual(events, ["create", "alert", "terminate"])
        XCTAssertNil(coordinator.modelContainer)
        XCTAssertNil(coordinator.clipboardHistoryWriter)
        XCTAssertNil(coordinator.clipboardMonitor)
        XCTAssertNil(coordinator.hotKeyManager)
        XCTAssertNil(coordinator.panelController)
        XCTAssertNil(coordinator.snippetEditorWindowController)
        let alert = try XCTUnwrap(presentedAlert)
        XCTAssertEqual(alert.alertStyle, .critical)
        XCTAssertEqual(alert.messageText, "Yank could not open its data store")
        XCTAssertTrue(alert.informativeText.contains("migration may have failed"))
        XCTAssertTrue(alert.informativeText.contains("left the existing store intact"))
        XCTAssertTrue(alert.informativeText.contains("without deleting or recreating it"))
        XCTAssertEqual(alert.buttons.map(\.title), ["Quit"])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(names))
        for name in names {
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent(name)),
                Data("preserve \(name)".utf8)
            )
        }
    }

    func testXCTestHostSkipsCoordinatorStartup() throws {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"])
        var events: [String] = []
        let coordinator = AppCoordinator(
            createModelContainer: {
                events.append("create")
                throw StartupError.migrationFailed
            },
            presentStoreError: { _ in events.append("alert") },
            terminate: { events.append("terminate") }
        )
        let delegate = AppDelegate(
            coordinator: coordinator,
            beginShutdown: {},
            finishShutdown: {},
            replyToTermination: { _, _ in }
        )

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(coordinator.modelContainer)
        XCTAssertNil(coordinator.clipboardMonitor)
        XCTAssertNil(coordinator.hotKeyManager)
    }
}
