//
//  MockKeychainService.swift
//  VultisigAppTests
//

import Foundation
import Security
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

    /// The answer ``getPasscodeAttemptState()`` gives, likewise.
    var passcodeAttemptStateResult: KeychainReadResult<Data> = .absent

    private var fastPasswords: [String: KeychainReadResult<String>] = [:]
    private var fastHints: [String: KeychainReadResult<String>] = [:]
    private var deviceTokenResult: KeychainReadResult<String> = .absent

    /// When set, `setKeyshareDataKey` accepts the write but stores nothing, so
    /// the read-back verification in `DefaultKeyshareKeyStore` can be exercised.
    var dropsKeyshareDataKeyWrites = false

    /// Same, for the wrapped copy: the write is accepted and nothing is stored,
    /// so the read-back verification that guards `setPasscode` can be driven.
    var dropsWrappedKeyshareDataKeyWrites = false

    /// When set, deletion of the clear data key silently does nothing, so the
    /// verified-deletion path can be exercised.
    var ignoresKeyshareDataKeyDeletion = false

    /// Same, for the wrapped copy, so the disable rollback can be exercised.
    var ignoresWrappedKeyshareDataKeyDeletion = false

    /// When set, deleting the wrapped copy **succeeds** but leaves the item
    /// unreadable. `deleteWrappedDataKey` verifies against a *confirmed*
    /// absence, so it reports `deletionFailed` over a deletion that in fact
    /// happened — the case a rollback must not read as "the wrapper is still
    /// there".
    var wrappedKeyshareDataKeyBecomesUnreadableOnDeletion = false

    /// When set, clearing the attempt state silently does nothing, so the
    /// verified clear in `KeyshareInstallReconciler` can be exercised.
    var ignoresPasscodeAttemptStateDeletion = false

    /// Every mutating call, in order, whether or not it changed anything.
    ///
    /// A delete of an item that was never there still reaches `SecItemDelete`,
    /// so it is a Keychain mutation as far as the acceptance test is concerned:
    /// a user who never sets a passcode must see none of them at launch. Only a
    /// counter can assert that — asserting on the stored values cannot tell a
    /// no-op write apart from no write at all.
    private(set) var writes: [String] = []

    func resetWrites() { writes = [] }

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

    /// The recorded attempt state, for tests that only care about the stored value.
    var passcodeAttemptState: Data? {
        get { passcodeAttemptStateResult.valueTreatingUnavailableAsAbsent }
        set { passcodeAttemptStateResult = Self.result(newValue) }
    }

    init(lastMigratedVersion: Int? = nil) {
        self.lastMigratedVersionResult = Self.result(lastMigratedVersion)
    }

    func getFastPassword(pubKeyECDSA: String) -> KeychainReadResult<String> {
        fastPasswords[pubKeyECDSA] ?? .absent
    }

    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String) {
        writes.append("fastPassword")
        fastPasswords[pubKeyECDSA] = Self.result(fastPassword)
    }

    func getFastHint(pubKeyECDSA: String) -> KeychainReadResult<String> {
        fastHints[pubKeyECDSA] ?? .absent
    }

    func setFastHint(_ fastHint: String?, pubKeyECDSA: String) {
        writes.append("fastHint")
        fastHints[pubKeyECDSA] = Self.result(fastHint)
    }

    func getLastMigratedVersion() -> KeychainReadResult<Int> { lastMigratedVersionResult }

    func setLastMigratedVersion(_ version: Int?) {
        writes.append("lastMigratedVersion")
        lastMigratedVersionResult = Self.result(version)
    }

    func getDeviceToken() -> KeychainReadResult<String> { deviceTokenResult }

    func setDeviceToken(_ token: String?) {
        writes.append("deviceToken")
        deviceTokenResult = Self.result(token)
    }

    func getKeyshareDataKey() -> KeychainReadResult<Data> { keyshareDataKeyResult }

    func setKeyshareDataKey(_ data: Data?) {
        writes.append("keyshareDataKey")
        guard !dropsKeyshareDataKeyWrites else { return }
        if data == nil && ignoresKeyshareDataKeyDeletion { return }
        keyshareDataKeyResult = Self.result(data)
    }

    func getWrappedKeyshareDataKey() -> KeychainReadResult<Data> { wrappedKeyshareDataKeyResult }

    func setWrappedKeyshareDataKey(_ data: Data?) {
        writes.append("wrappedKeyshareDataKey")
        if data != nil && dropsWrappedKeyshareDataKeyWrites { return }
        if data == nil && ignoresWrappedKeyshareDataKeyDeletion { return }
        if data == nil && wrappedKeyshareDataKeyBecomesUnreadableOnDeletion {
            wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)
            return
        }
        wrappedKeyshareDataKeyResult = Self.result(data)
    }

    func getPasscodeAttemptState() -> KeychainReadResult<Data> { passcodeAttemptStateResult }

    func setPasscodeAttemptState(_ data: Data?) {
        writes.append("passcodeAttemptState")
        if data == nil && ignoresPasscodeAttemptStateDeletion { return }
        passcodeAttemptStateResult = Self.result(data)
    }

    private static func result<Value>(_ value: Value?) -> KeychainReadResult<Value> {
        guard let value else { return .absent }
        return .present(value)
    }
}
