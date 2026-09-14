import CryptoKit
import Darwin
import Foundation

/// A file cache shared by the app and extensions. Only opaque SHA256 keys cross process boundaries.
public struct RemoteImageCache: Sendable {
    public static let maximumImageBytes = 512 * 1_024
    private static let maximumCacheBytes = 64 * 1_024 * 1_024
    private static let retention: TimeInterval = 7 * 24 * 60 * 60
    private static let minimumRetention: TimeInterval = 8 * 60 * 60
    private let directory: URL?

    /// A nil directory disables persistence, including synchronous widget reads.
    public init(directory: URL?) {
        self.directory = directory
    }

    /// Extensions should keep the default: missing group access disables persistence.
    /// The containing app may explicitly opt into a local cache fallback.
    public static func shared(
        appGroupIdentifier: String = "group.com.vultisig.wallet",
        allowLocalFallback: Bool = false
    ) -> Self {
        let manager = FileManager.default
        let root = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? (allowLocalFallback ? manager.urls(for: .cachesDirectory, in: .userDomainMask).first : nil)
        return Self(directory: root?.appendingPathComponent("SharedRemoteImages", isDirectory: true))
    }

    public static func key(for url: URL) -> String? {
        guard isAllowed(url) else { return nil }
        return SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    private static func validKey(_ key: String) -> Bool {
        key.utf8.count == 64 && key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Reads at most one bounded file; never follows a URL or interprets a key as a path.
    public func data(forKey key: String) -> Data? {
        guard Self.validKey(key), let directory else { return nil }
        let file = directory.appendingPathComponent(key)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let modified = values.contentModificationDate,
              Date().timeIntervalSince(modified) < Self.retention,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumImageBytes + 1),
              !data.isEmpty, data.count <= Self.maximumImageBytes else { return nil }
        return data
    }

    /// Atomically stores prepared PNG data. A full cache preserves images less than eight hours old.
    /// Cache failures are optional to callers: the downloaded image can still be displayed.
    public func store(_ data: Data, forKey key: String) throws {
        guard Self.validKey(key), !data.isEmpty, data.count <= Self.maximumImageBytes else {
            throw RemoteImageError.invalidImage
        }
        guard let directory else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // flock also serializes writers from the app and its extensions.
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RemoteImageError.cacheUnavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw RemoteImageError.cacheUnavailable }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        var entries: [(url: URL, bytes: Int, modified: Date)] = []
        for file in files where Self.validKey(file.lastPathComponent) && file.lastPathComponent != key {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            entries.append((file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        var total = entries.reduce(data.count) { $0 + $1.bytes }
        let now = Date()
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            let age = now.timeIntervalSince(entry.modified)
            if age >= Self.retention || (total > Self.maximumCacheBytes && age >= Self.minimumRetention) {
                try manager.removeItem(at: entry.url)
                total -= entry.bytes
            }
        }
        guard total <= Self.maximumCacheBytes else { throw RemoteImageError.cacheFull }
        try Task.checkCancellation()
        try data.write(to: directory.appendingPathComponent(key), options: .atomic)
    }
}
