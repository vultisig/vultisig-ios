//
//  MockKeychainService.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp

/// In-memory `KeychainService` so migration-ordering behaviour can be driven
/// without touching the real Keychain (which persists across test runs and
/// across app reinstalls).
final class MockKeychainService: KeychainService {
    var lastMigratedVersion: Int?

    private var fastPasswords: [String: String] = [:]
    private var fastHints: [String: String] = [:]
    private var deviceToken: String?
    private var keyshareDataKey: Data?
    private var wrappedKeyshareDataKey: Data?
    private var passcodeAttemptState: Data?

    /// When set, `setKeyshareDataKey` accepts the write but stores nothing, so
    /// the read-back verification in `DefaultKeyshareKeyStore` can be exercised.
    var dropsKeyshareDataKeyWrites = false

    /// When set, deletion of the clear data key silently does nothing, so the
    /// verified-deletion path can be exercised.
    var ignoresKeyshareDataKeyDeletion = false

    /// Same, for the wrapped copy, so the disable rollback can be exercised.
    var ignoresWrappedKeyshareDataKeyDeletion = false

    init(lastMigratedVersion: Int? = nil) {
        self.lastMigratedVersion = lastMigratedVersion
    }

    func getFastPassword(pubKeyECDSA: String) -> String? { fastPasswords[pubKeyECDSA] }

    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String) {
        fastPasswords[pubKeyECDSA] = fastPassword
    }

    func getFastHint(pubKeyECDSA: String) -> String? { fastHints[pubKeyECDSA] }

    func setFastHint(_ fastHint: String?, pubKeyECDSA: String) {
        fastHints[pubKeyECDSA] = fastHint
    }

    func getLastMigratedVersion() -> Int? { lastMigratedVersion }

    func setLastMigratedVersion(_ version: Int?) { lastMigratedVersion = version }

    func getDeviceToken() -> String? { deviceToken }

    func setDeviceToken(_ token: String?) { deviceToken = token }

    func getKeyshareDataKey() -> Data? { keyshareDataKey }

    func setKeyshareDataKey(_ data: Data?) {
        guard !dropsKeyshareDataKeyWrites else { return }
        if data == nil && ignoresKeyshareDataKeyDeletion { return }
        keyshareDataKey = data
    }

    func getWrappedKeyshareDataKey() -> Data? { wrappedKeyshareDataKey }

    func setWrappedKeyshareDataKey(_ data: Data?) {
        if data == nil && ignoresWrappedKeyshareDataKeyDeletion { return }
        wrappedKeyshareDataKey = data
    }

    func getPasscodeAttemptState() -> Data? { passcodeAttemptState }

    func setPasscodeAttemptState(_ data: Data?) { passcodeAttemptState = data }
}
