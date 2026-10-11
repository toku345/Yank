import SwiftData
import XCTest
@testable import Yank

@MainActor
final class AppCoordinatorStartupFailureTests: XCTestCase {
    private struct StubFailure: Error {}

    func testStart_whenStoreCannotBeOpened_reportsFailureAndSkipsStartup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A stand-in for the user's store: the failure path must not modify it.
        let storeURL = directory.appendingPathComponent("Yank.store")
        let existingStoreBytes = Data("existing store bytes".utf8)
        try existingStoreBytes.write(to: storeURL)

        var presentedAlerts: [StartupFailureAlert] = []
        let coordinator = AppCoordinator(
            storeURL: storeURL,
            makeModelContainer: { _, _ in throw StubFailure() },
            presentStartupFailure: { presentedAlerts.append($0) }
        )

        coordinator.start()

        XCTAssertEqual(presentedAlerts.count, 1)
        XCTAssertEqual(presentedAlerts.first?.informativeText.contains(storeURL.path), true)
        XCTAssertEqual(try Data(contentsOf: storeURL), existingStoreBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Yank.store"])
        XCTAssertNil(coordinator.modelContainer)
        XCTAssertNil(coordinator.clipboardHistoryWriter)
        XCTAssertNil(coordinator.clipboardMonitor)
        XCTAssertNil(coordinator.hotKeyManager)
        XCTAssertNil(coordinator.panelController)
        XCTAssertNil(coordinator.snippetEditorWindowController)
    }

    func testStartupFailureAlert_statesTheStoreWasLeftIntact() {
        let storeURL = URL(fileURLWithPath: "/tmp/Yank-66/Yank.store")

        let alert = StartupFailureAlert(error: StubFailure(), storeURL: storeURL)

        XCTAssertTrue(alert.messageText.contains("could not open"))
        XCTAssertTrue(alert.informativeText.contains(storeURL.path))
        XCTAssertTrue(alert.informativeText.contains("did not delete or recreate the store"))
        XCTAssertTrue(alert.informativeText.contains("migrated"))
    }

    func testStart_withDefaultStoreLocation_reportsThePathItTriedToOpen() throws {
        var presentedAlerts: [StartupFailureAlert] = []
        let coordinator = AppCoordinator(
            makeModelContainer: { _, _ in throw StubFailure() },
            presentStartupFailure: { presentedAlerts.append($0) }
        )

        coordinator.start()

        let informativeText = try XCTUnwrap(presentedAlerts.first).informativeText
        XCTAssertTrue(informativeText.contains("Application Support/Yank.store"))
    }

    func testOpenStore_throwsForAnUnopenableStorePathWithoutTouchingIt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A directory at the store URL cannot be opened as a SQLite-backed store,
        // which is what makes the startup failure path reachable in production.
        let storeURL = directory.appendingPathComponent("Yank.store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        let sentinel = storeURL.appendingPathComponent("sentinel.txt")
        try Data("keep me".utf8).write(to: sentinel)

        let schema = YankSchema.current
        let configuration = ModelConfiguration("Yank", schema: schema, url: storeURL)

        XCTAssertThrowsError(try AppCoordinator.openStore(schema: schema, configuration: configuration))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Yank.store"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: storeURL.path), ["sentinel.txt"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YankStartupFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
