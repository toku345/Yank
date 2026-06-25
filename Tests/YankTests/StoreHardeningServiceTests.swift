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

        // A store-family-named symlink must not be followed: hardening it would chmod the
        // (possibly attacker- or app-pointed) target. Use a family suffix (-journal) so the
        // entry reaches the classify symlink guard rather than being filtered out by name.
        let target = try makeTemporaryDirectory().appendingPathComponent("external-secret")
        fileManager.createFile(atPath: target.path, contents: Data("target".utf8))
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let symlink = directory.appendingPathComponent("Yank.store-journal")
        try fileManager.createSymbolicLink(atPath: symlink.path, withDestinationPath: target.path)

        let report = StoreHardeningService(directory: directory).hardenStoreFamily()

        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(report.files.map(\.url.lastPathComponent).contains("Yank.store-journal"))
        XCTAssertEqual(try permissions(for: target), 0o644)
    }

    func testExcludesStorePrefixedFileOutsideKnownSuffixes() throws {
        let directory = try makeTemporaryDirectory()
        try createStoreFamilyFiles(in: directory)

        // hasPrefix("Yank.store") would also match unrelated artifacts; only the known SQLite
        // sidecar suffixes should be hardened, leaving e.g. a backup file untouched.
        let unrelated = directory.appendingPathComponent("Yank.store.bak")
        fileManager.createFile(atPath: unrelated.path, contents: Data("backup".utf8))
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unrelated.path)

        let report = StoreHardeningService(directory: directory).hardenStoreFamily()

        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(report.files.map(\.url.lastPathComponent).contains("Yank.store.bak"))
        XCTAssertEqual(try permissions(for: unrelated), 0o644)
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

    func testRecordsFailureWhenFileInspectionThrows() throws {
        let directory = try makeTemporaryDirectory()
        let storeFiles = try createStoreFamilyFiles(in: directory)

        // When resourceValues cannot determine the file kind, the entry must be reported as a
        // failure rather than silently dropped — otherwise an unverifiable store file is left
        // at its prior permissions while the report claims success (the pre-fix bug).
        let service = StoreHardeningService(
            directory: directory,
            inspectFileKind: { _ in throw TestError.inspectionFailed }
        )

        let report = service.hardenStoreFamily()

        XCTAssertFalse(report.succeeded)
        XCTAssertEqual(report.failures.count, storeFiles.count)
        XCTAssertTrue(report.files.isEmpty)
    }

    func testRecordsFailureWhenProtectionSupportProbeThrows() throws {
        let directory = try makeTemporaryDirectory()
        let storeFiles = try createStoreFamilyFiles(in: directory)

        // A failing protection-support probe must be recorded as a failure (not silently
        // treated as verified), while owner-only permissions are still applied.
        let service = StoreHardeningService(
            directory: directory,
            inspectVolumeProtectionSupport: { _ in throw TestError.inspectionFailed }
        )

        let report = service.hardenStoreFamily()

        XCTAssertFalse(report.succeeded)
        XCTAssertEqual(report.failures.count, storeFiles.count)
        XCTAssertEqual(report.files.count, storeFiles.count)
        for url in storeFiles {
            XCTAssertEqual(try permissions(for: url), 0o600)
        }
    }

    private enum TestError: Error {
        case inspectionFailed
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
