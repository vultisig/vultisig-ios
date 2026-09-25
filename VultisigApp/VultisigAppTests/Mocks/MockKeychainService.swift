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
///
/// `@unchecked Sendable`: everything mutable lives in `state`, which is only
/// touched while holding `lock`.
final class MockKeychainService: KeychainService, @unchecked Sendable {

    private struct State {
        var lastMigratedVersionResult: KeychainReadResult<Int>
        var wrappedKeyshareDataKeyResult: KeychainReadResult<Data> = .absent
        var passcodeAttemptStateResult: KeychainReadResult<Data> = .absent
        var fastPasswords: [String: KeychainReadResult<String>] = [:]
        var fastHints: [String: KeychainReadResult<String>] = [:]
        var deviceTokenResult: KeychainReadResult<String> = .absent
        var dropsWrappedKeyshareDataKeyWrites = false
        var ignoresWrappedKeyshareDataKeyDeletion = false
        var wrappedKeyshareDataKeyBecomesUnreadableOnDeletion = false
        var ignoresPasscodeAttemptStateDeletion = false
        var writes: [String] = []
    }

    private let lock = NSLock()
    private var state: State

    /// The answer ``getLastMigratedVersion()`` gives. Settable directly so a
    /// test can stage `.unavailable`.
    var lastMigratedVersionResult: KeychainReadResult<Int> {
        get { withState { $0.lastMigratedVersionResult } }
        set { withState { $0.lastMigratedVersionResult = newValue } }
    }

    /// The answer ``getWrappedKeyshareDataKey()`` gives, likewise.
    var wrappedKeyshareDataKeyResult: KeychainReadResult<Data> {
        get { withState { $0.wrappedKeyshareDataKeyResult } }
        set { withState { $0.wrappedKeyshareDataKeyResult = newValue } }
    }

    /// The answer ``getPasscodeAttemptState()`` gives, likewise.
    var passcodeAttemptStateResult: KeychainReadResult<Data> {
        get { withState { $0.passcodeAttemptStateResult } }
        set { withState { $0.passcodeAttemptStateResult = newValue } }
    }

    /// When set, the write is accepted and nothing is stored, so the read-back
    /// verification that guards `setPasscode` can be driven.
    var dropsWrappedKeyshareDataKeyWrites: Bool {
        get { withState { $0.dropsWrappedKeyshareDataKeyWrites } }
        set { withState { $0.dropsWrappedKeyshareDataKeyWrites = newValue } }
    }

    /// When set, deleting the wrapped copy silently does nothing, so the
    /// verified-deletion path and the disable rollback can be exercised.
    var ignoresWrappedKeyshareDataKeyDeletion: Bool {
        get { withState { $0.ignoresWrappedKeyshareDataKeyDeletion } }
        set { withState { $0.ignoresWrappedKeyshareDataKeyDeletion = newValue } }
    }

    /// When set, deleting the wrapped copy **succeeds** but leaves the item
    /// unreadable. `deleteWrappedDataKey` verifies against a *confirmed*
    /// absence, so it reports `deletionFailed` over a deletion that in fact
    /// happened — the case a rollback must not read as "the wrapper is still
    /// there".
    var wrappedKeyshareDataKeyBecomesUnreadableOnDeletion: Bool {
        get { withState { $0.wrappedKeyshareDataKeyBecomesUnreadableOnDeletion } }
        set { withState { $0.wrappedKeyshareDataKeyBecomesUnreadableOnDeletion = newValue } }
    }

    /// When set, clearing the attempt state silently does nothing, so the
    /// verified clear in `KeyshareInstallReconciler` can be exercised.
    var ignoresPasscodeAttemptStateDeletion: Bool {
        get { withState { $0.ignoresPasscodeAttemptStateDeletion } }
        set { withState { $0.ignoresPasscodeAttemptStateDeletion = newValue } }
    }

    /// Every mutating call, in order, whether or not it changed anything.
    ///
    /// A delete of an item that was never there still reaches `SecItemDelete`,
    /// so it is a Keychain mutation as far as the acceptance test is concerned:
    /// a user who never sets a passcode must see none of them at launch. Only a
    /// counter can assert that — asserting on the stored values cannot tell a
    /// no-op write apart from no write at all.
    var writes: [String] { withState { $0.writes } }

    func resetWrites() { withState { $0.writes = [] } }

    /// The recorded version, for tests that only care about the stored value.
    var lastMigratedVersion: Int? {
        get { lastMigratedVersionResult.valueTreatingUnavailableAsAbsent }
        set { lastMigratedVersionResult = Self.result(newValue) }
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
        self.state = State(lastMigratedVersionResult: Self.result(lastMigratedVersion))
    }

    func getFastPassword(pubKeyECDSA: String) -> KeychainReadResult<String> {
        withState { $0.fastPasswords[pubKeyECDSA] ?? .absent }
    }

    func setFastPassword(_ fastPassword: String?, pubKeyECDSA: String) {
        withState { state in
            state.writes.append("fastPassword")
            state.fastPasswords[pubKeyECDSA] = Self.result(fastPassword)
        }
    }

    func getFastHint(pubKeyECDSA: String) -> KeychainReadResult<String> {
        withState { $0.fastHints[pubKeyECDSA] ?? .absent }
    }

    func setFastHint(_ fastHint: String?, pubKeyECDSA: String) {
        withState { state in
            state.writes.append("fastHint")
            state.fastHints[pubKeyECDSA] = Self.result(fastHint)
        }
    }

    func getLastMigratedVersion() -> KeychainReadResult<Int> { lastMigratedVersionResult }

    func setLastMigratedVersion(_ version: Int?) {
        withState { state in
            state.writes.append("lastMigratedVersion")
            state.lastMigratedVersionResult = Self.result(version)
        }
    }

    func getDeviceToken() -> KeychainReadResult<String> { withState { $0.deviceTokenResult } }

    func setDeviceToken(_ token: String?) {
        withState { state in
            state.writes.append("deviceToken")
            state.deviceTokenResult = Self.result(token)
        }
    }

    func getWrappedKeyshareDataKey() -> KeychainReadResult<Data> { wrappedKeyshareDataKeyResult }

    func setWrappedKeyshareDataKey(_ data: Data?) {
        withState { state in
            state.writes.append("wrappedKeyshareDataKey")
            if data != nil && state.dropsWrappedKeyshareDataKeyWrites { return }
            if data == nil && state.ignoresWrappedKeyshareDataKeyDeletion { return }
            if data == nil && state.wrappedKeyshareDataKeyBecomesUnreadableOnDeletion {
                state.wrappedKeyshareDataKeyResult = .unavailable(errSecInteractionNotAllowed)
                return
            }
            state.wrappedKeyshareDataKeyResult = Self.result(data)
        }
    }

    func getPasscodeAttemptState() -> KeychainReadResult<Data> { passcodeAttemptStateResult }

    func setPasscodeAttemptState(_ data: Data?) {
        withState { state in
            state.writes.append("passcodeAttemptState")
            if data == nil && state.ignoresPasscodeAttemptStateDeletion { return }
            state.passcodeAttemptStateResult = Self.result(data)
        }
    }

    /// The lock is not recursive, so `body` must touch only the state it is
    /// handed, never another member of this mock.
    private func withState<T>(_ body: (inout State) -> T) -> T {
        lock.withLock { body(&state) }
    }

    private static func result<Value>(_ value: Value?) -> KeychainReadResult<Value> {
        guard let value else { return .absent }
        return .present(value)
    }
}
