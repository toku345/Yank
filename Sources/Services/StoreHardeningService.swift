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

private enum StoreFileClassification {
    case harden
    case skip
    case inspectionFailed(String)
}

struct StoreFileKind {
    let isRegularFile: Bool
    let isSymbolicLink: Bool
}

struct StoreHardeningService {
    static let defaultStoreBaseName = "Yank.store"
    // The main store plus the SQLite sidecars SwiftData can produce. Matching exact suffixes
    // (rather than a bare prefix) avoids chmodding unrelated files like Yank.store.bak.
    private static let storeFamilySuffixes = ["", "-wal", "-shm", "-journal"]

    private let directory: URL
    private let storeBaseName: String
    private let fileManager: FileManager
    // Resource inspection is injected so the "could not inspect / could not determine
    // support" error paths are reachable in tests; the real FileManager seam cannot make
    // URL.resourceValues throw on demand.
    private let inspectFileKind: (URL) throws -> StoreFileKind
    private let inspectVolumeProtectionSupport: (URL) throws -> Bool

    init(
        directory: URL = Self.defaultStoreDirectory(),
        storeBaseName: String = Self.defaultStoreBaseName,
        fileManager: FileManager = .default,
        inspectFileKind: @escaping (URL) throws -> StoreFileKind = Self.defaultInspectFileKind,
        inspectVolumeProtectionSupport: @escaping (URL) throws -> Bool = Self.defaultVolumeProtectionSupport
    ) {
        self.directory = directory
        self.storeBaseName = storeBaseName
        self.fileManager = fileManager
        self.inspectFileKind = inspectFileKind
        self.inspectVolumeProtectionSupport = inspectVolumeProtectionSupport
    }

    static func defaultInspectFileKind(_ url: URL) throws -> StoreFileKind {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return StoreFileKind(
            isRegularFile: values.isRegularFile ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false
        )
    }

    static func defaultVolumeProtectionSupport(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.volumeSupportsFileProtectionKey])
        return (values.allValues[.volumeSupportsFileProtectionKey] as? Bool) ?? false
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
            switch classify(url) {
            case .harden:
                harden(url, report: &report)
            case .skip:
                continue
            case .inspectionFailed(let description):
                report.failures.append(StoreHardeningFailure(url: url, description: description))
            }
        }
        return report
    }

    private static func defaultStoreDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    // Known gap: hardening runs once at launch. SQLite creates the -wal/-shm sidecars lazily
    // on the first write transaction, so on a first launch (or after the sidecars are removed)
    // they are created at the process umask default and stay that way until the next launch
    // reapplies hardening. This is accepted under ADR 0006's best-effort scope; see the ADR's
    // Security Limitations.
    private func storeFamilyURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        .filter(isStoreFamilyFile)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isStoreFamilyFile(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent
        return Self.storeFamilySuffixes.contains { fileName == storeBaseName + $0 }
    }

    // A store-family-named entry is hardened only when we can confirm it is a regular,
    // non-symlink file. Symlinks and non-regular files are intentionally skipped (hardening
    // must not follow a symlink onto an unintended target). An inspection error means we
    // could not determine the kind, which is reported as a failure rather than silently
    // dropped — otherwise an unverifiable store file would be left at its prior permissions
    // while the report still claimed success.
    private func classify(_ url: URL) -> StoreFileClassification {
        let kind: StoreFileKind
        do {
            kind = try inspectFileKind(url)
        } catch {
            return .inspectionFailed("could not inspect store file: \(error.localizedDescription)")
        }
        guard kind.isRegularFile, !kind.isSymbolicLink else {
            return .skip
        }
        return .harden
    }

    private func harden(_ url: URL, report: inout StoreHardeningReport) {
        let supportsFileProtection = fileProtectionSupport(for: url, report: &report)
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

    // Returns nil when the volume's file-protection support could not be determined. That
    // case is recorded as a failure (mirroring classify's inspectionFailed) so the report
    // does not claim a clean success while the protection class was never confirmed; owner-only
    // permissions are still applied by the caller regardless.
    private func fileProtectionSupport(for url: URL, report: inout StoreHardeningReport) -> Bool? {
        do {
            return try inspectVolumeProtectionSupport(url)
        } catch {
            report.failures.append(StoreHardeningFailure(
                url: url,
                description: "could not determine file protection support: \(error.localizedDescription)"
            ))
            return nil
        }
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
