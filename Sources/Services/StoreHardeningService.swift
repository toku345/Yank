import Foundation

struct StoreHardeningReport {
    var files: [StoreHardeningFileResult] = []
    var failures: [StoreHardeningFailure] = []

    var succeeded: Bool { failures.isEmpty }

    var fileProtectionUnsupportedCount: Int {
        files.filter { $0.volumeSupportsFileProtection == false }.count
    }
}

struct StoreHardeningFileResult {
    let url: URL
    let ownerOnlyPermissionsVerified: Bool
    let volumeSupportsFileProtection: Bool?
    let fileProtection: URLFileProtection?

    var fileProtectionVerified: Bool {
        guard volumeSupportsFileProtection == true else { return true }
        return fileProtection != nil && fileProtection != URLFileProtection.none
    }
}

struct StoreHardeningFailure: Error {
    let url: URL
    let description: String
}

struct StoreHardeningService {
    static let defaultStoreBaseName = "Yank.store"

    private let directory: URL
    private let storeBaseName: String
    private let fileManager: FileManager

    init(
        directory: URL = Self.defaultStoreDirectory(),
        storeBaseName: String = Self.defaultStoreBaseName,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.storeBaseName = storeBaseName
        self.fileManager = fileManager
    }

    func hardenStoreFamily() -> StoreHardeningReport {
        var report = StoreHardeningReport()
        let storeFiles: [URL]
        do {
            storeFiles = try storeFamilyURLs()
        } catch {
            report.failures.append(StoreHardeningFailure(url: directory, description: error.localizedDescription))
            return report
        }

        for url in storeFiles {
            harden(url, report: &report)
        }
        return report
    }

    private static func defaultStoreDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    private func storeFamilyURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        .filter(isStoreFamilyFile)
        .filter(isRegularNonSymlinkFile)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isStoreFamilyFile(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent
        return fileName.hasPrefix(storeBaseName)
    }

    private func isRegularNonSymlinkFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private func harden(_ url: URL, report: inout StoreHardeningReport) {
        let supportsFileProtection = volumeSupportsFileProtection(url)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        if supportsFileProtection == true {
            attributes[.protectionKey] = FileProtectionType.completeUnlessOpen
        }

        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
            let result = try verify(url, volumeSupportsFileProtection: supportsFileProtection)
            report.files.append(result)
            if !result.ownerOnlyPermissionsVerified {
                report.failures.append(StoreHardeningFailure(
                    url: url,
                    description: "owner-only permissions not applied"
                ))
            }
            if !result.fileProtectionVerified {
                report.failures.append(StoreHardeningFailure(url: url, description: "file protection not applied"))
            }
        } catch {
            report.failures.append(StoreHardeningFailure(url: url, description: error.localizedDescription))
        }
    }

    private func volumeSupportsFileProtection(_ url: URL) -> Bool? {
        let values = try? url.resourceValues(forKeys: [.volumeSupportsFileProtectionKey])
        return values?.allValues[.volumeSupportsFileProtectionKey] as? Bool
    }

    private func verify(
        _ url: URL,
        volumeSupportsFileProtection: Bool?
    ) throws -> StoreHardeningFileResult {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let values = try url.resourceValues(forKeys: [.fileProtectionKey])

        return StoreHardeningFileResult(
            url: url,
            ownerOnlyPermissionsVerified: permissions & 0o777 == 0o600,
            volumeSupportsFileProtection: volumeSupportsFileProtection,
            fileProtection: values.allValues[.fileProtectionKey] as? URLFileProtection
        )
    }
}
