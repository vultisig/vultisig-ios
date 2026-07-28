//
//  MockKeychainService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

/// In-memory `KeychainService` so migration-ordering behaviour can be driven
/// without touching the real Keychain (which persists across test runs and
/// across app reinstalls).
///
/// Values are held as `KeychainReadResult`s rather than optionals so a test can
/// stage an unreadable Keychain as easily as a stored value — the two are
/// different answers and the consumers have to be pinned against both. That
/// matters most for the key material below, where "absent" licenses minting a
/// replacement and "unavailable" must not.
final class MockKeychainService: KeychainService {

    /// The answer ``getLastMigratedVersion()`` gives. Settable directly so a
    /// test can stage `.unavailable`.
    var lastMigratedVersionResult: KeychainReadResult<Int>

    /// The answer ``getKeyshareDataKey()`` gives, likewise.
    var keyshareDataKeyResult: KeychainReadResult<Data> = .absent

    /// The answer ``getWrappedKeyshareDataKey()`` gives, likewise.
    var wrappedKeyshareDataKeyResult: KeychainReadResult<Data> = .absent

    private var fastPasswords: [String: KeychainReadResult<String>] = [:]
    private var fastHints: [String: KeychainReadResult<String>] = [:]
    private var deviceTokenResult: KeychainReadResult<String> = .absent

    /// When set, `setKeyshareDataKey` accepts the write but stores nothing, so
    /// the read-back verification in `DefaultKeyshareKeyStore` can be exercised.
    var dropsKeyshareDataKeyWrites = false

    /// The recorded version, for tests that only care about the stored value.
    var lastMigratedVersion: Int? {
        get { lastMigratedVersionResult.valueTreatingUnavailableAsAbsent }
        set { lastMigratedVersionResult = Self.result(newValue) }
    }

    /// The recorded key, for tests that only care about the stored value.
    var keyshareDataKey: Data? {
        get { keyshareDataKeyResult.valueTreatingUnavailableAsAbsent }
        set { keyshareDataKeyResult = Self.result(newValue) }
    }

    /// The recorded wrapped key, for tests that only care about the stored value.
    var wrappedKeyshareDataKey: Data? {
        get { wrappedKeyshareDataKeyResult.valueTreatingUnavailableAsAbsent }
        set { wrappedKeyshareDataKeyResult = Self.result(newValue) }
    }

    init(lastMigratedVersion: Int? = nil) {
        self.lastMigratedVersionResult = Self.result(lastMigratedVersion)
    }

    func getFastPassword(pubKeyECDSA: String) -> KeychainReadResult<String> {
        fastPasswords[pubKeyECDSA] ?? .absent
    }

    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String) {
        fastPasswords[pubKeyECDSA] = Self.result(fastPassword)
    }

    func getFastHint(pubKeyECDSA: String) -> KeychainReadResult<String> {
        fastHints[pubKeyECDSA] ?? .absent
    }

    func setFastHint(_ fastHint: String?, pubKeyECDSA: String) {
        fastHints[pubKeyECDSA] = Self.result(fastHint)
    }

    func getLastMigratedVersion() -> KeychainReadResult<Int> { lastMigratedVersionResult }

    func setLastMigratedVersion(_ version: Int?) { lastMigratedVersionResult = Self.result(version) }

    func getDeviceToken() -> KeychainReadResult<String> { deviceTokenResult }

    func setDeviceToken(_ token: String?) { deviceTokenResult = Self.result(token) }

    func getKeyshareDataKey() -> KeychainReadResult<Data> { keyshareDataKeyResult }

    func setKeyshareDataKey(_ data: Data?) {
        guard !dropsKeyshareDataKeyWrites else { return }
        keyshareDataKeyResult = Self.result(data)
    }

    func getWrappedKeyshareDataKey() -> KeychainReadResult<Data> { wrappedKeyshareDataKeyResult }

    func setWrappedKeyshareDataKey(_ data: Data?) {
        wrappedKeyshareDataKeyResult = Self.result(data)
    }

    private static func result<Value>(_ value: Value?) -> KeychainReadResult<Value> {
        guard let value else { return .absent }
        return .present(value)
    }
}
