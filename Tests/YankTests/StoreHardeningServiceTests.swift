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
