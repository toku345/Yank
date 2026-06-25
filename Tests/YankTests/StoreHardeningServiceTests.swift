import Foundation
import XCTest
@testable import Yank

final class StoreHardeningServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testAppliesOwnerOnlyPermissionsToStoreFamily() throws {
        let directory = try makeTemporaryDirectory()
        let storeFiles = try createStoreFamilyFiles(in: directory)

        let report = StoreHardeningService(directory: directory).hardenStoreFamily()

        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(Set(report.files.map { $0.url.lastPathComponent }), Set(storeFiles.map(\.lastPathComponent)))
        for url in storeFiles {
            XCTAssertEqual(try permissions(for: url), 0o600)
        }
    }

    func testAppliesFileProtectionWhenVolumeSupportsIt() throws {
        let directory = try makeTemporaryDirectory()
        try createStoreFamilyFiles(in: directory)

        let report = StoreHardeningService(directory: directory).hardenStoreFamily()

        XCTAssertTrue(report.succeeded)
        for result in report.files where result.volumeSupportsFileProtection == true {
            XCTAssertTrue(result.fileProtectionVerified)
            XCTAssertNotEqual(result.fileProtection, .none)
        }
    }

    func testEmptyStoreFamilyIsNoOp() throws {
        let directory = try makeTemporaryDirectory()

        let report = StoreHardeningService(directory: directory).hardenStoreFamily()

        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(report.files.isEmpty)
    }

    func testExcludesSymlinkAndLeavesTargetUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        try createStoreFamilyFiles(in: directory)

        // A symlink whose name matches the store prefix must not be followed: hardening it
        // would chmod the (possibly attacker- or app-pointed) target.
        let target = try makeTemporaryDirectory().appendingPathComponent("external-secret")
        fileManager.createFile(atPath: target.path, contents: Data("target".utf8))
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let symlink = directory.appendingPathComponent("Yank.store-link")
        try fileManager.createSymbolicLink(atPath: symlink.path, withDestinationPath: target.path)

        let report = StoreHardeningService(directory: directory).hardenStoreFamily()

        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(report.files.map(\.url.lastPathComponent).contains("Yank.store-link"))
        XCTAssertEqual(try permissions(for: target), 0o644)
    }

    func testReportsFailureWhenDirectoryCannotBeListed() throws {
        // Point the service at a regular file rather than a directory: it exists, so the
        // fileExists guard passes, but contentsOfDirectory throws. This exercises the
        // failure-reporting contract AppCoordinator relies on to emit its error log.
        let parent = try makeTemporaryDirectory()
        let notADirectory = parent.appendingPathComponent("Yank.store")
        fileManager.createFile(atPath: notADirectory.path, contents: Data("fixture".utf8))

        let report = StoreHardeningService(directory: notADirectory).hardenStoreFamily()

        XCTAssertFalse(report.succeeded)
        XCTAssertFalse(report.failures.isEmpty)
        XCTAssertTrue(report.files.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("YankStoreHardeningTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? self.fileManager.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func createStoreFamilyFiles(in directory: URL) throws -> [URL] {
        let files = ["Yank.store", "Yank.store-wal", "Yank.store-shm"].map {
            directory.appendingPathComponent($0)
        }
        for url in files {
            fileManager.createFile(atPath: url.path, contents: Data("fixture".utf8))
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        return files
    }

    private func permissions(for url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}
