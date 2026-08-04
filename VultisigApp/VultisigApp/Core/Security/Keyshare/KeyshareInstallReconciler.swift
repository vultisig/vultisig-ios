//
//  KeyshareInstallReconciler.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftData

private let logger = Log.app.store

/// Brings Keychain-held key material back into agreement with the app container
/// at launch.
///
/// The Keychain outlives the app. Deleting the app removes the SwiftData store
/// and every `UserDefaults` value, but leaves every Keychain item exactly where
/// it was — so a reinstall begins with no vaults and no lock mode while the data
/// key, its wrapped copy and the attempt counter all survive.
///
/// Once a passcode exists that asymmetry is fatal. `AppLockService.mode` lives in
/// `UserDefaults`, so it reverts to device auth and the passcode screen is never
/// shown; the wrapped data key lives in the Keychain, so `KeyshareKeySession`
/// reports `.locked`. Nothing can open the key and nothing can ask for the
/// passcode, so every vault created or imported afterwards fails to seal — and
/// deleting the app again, the obvious way out, is what caused it.
///
/// Two things are reconciled, in order:
///
/// 1. **Inherited key material** is cleared when the container is new. Bounded by
///    two conditions so it can never destroy a key something depends on.
/// 2. **The lock mode** is forced back to `.passcode` whenever a wrapped key
///    exists without a clear one, so key material always has a door in front of
///    it even if the first step could not run.
///
/// Runs on every launch, before migrations.
struct KeyshareInstallReconciler {

    enum ReconcileError: Error, Equatable {
        /// A Keychain item was still readable after being cleared.
        case clearFailed(item: String)
    }

    /// Marks a container that has already been reconciled.
    ///
    /// In `UserDefaults` deliberately: it has to disappear along with the
    /// container, because its *absence* is the only evidence that the container
    /// is new. Anything Keychain-held would survive the reinstall it is meant to
    /// detect.
    private static let markerKey = "keyshareInstallReconciled"

    private let keychain: KeychainService
    private let keyStore: KeyshareKeyStoring
    private let lockService: AppLockService
    private let defaults: UserDefaults

    init(
        keychain: KeychainService = DefaultKeychainService.shared,
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared,
        lockService: AppLockService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.keyStore = keyStore
        self.lockService = lockService
        self.defaults = defaults
    }

    @MainActor
    func reconcile() {
        // A store that cannot be read counts as "not empty". Being unable to
        // tell must never be mistaken for a new container.
        var isStoreEmpty = false
        if let context = Storage.shared.modelContext,
           let count = try? context.fetchCount(FetchDescriptor<Vault>()) {
            isStoreEmpty = count == 0
        }
        reconcile(isStoreEmpty: isStoreEmpty)
    }

    func reconcile(isStoreEmpty: Bool) {
        clearInheritedKeyMaterialIfContainerIsNew(isStoreEmpty: isStoreEmpty)
        restoreLockModeIfKeyIsWrapped()
    }

    // MARK: - Inherited key material

    private func clearInheritedKeyMaterialIfContainerIsNew(isStoreEmpty: Bool) {
        guard !defaults.bool(forKey: Self.markerKey) else { return }

        // Existing users reach this line exactly once, on the first launch of the
        // build that introduces the marker — with a full store. Clearing their
        // data key would orphan every sealed share, which in this app is lost
        // funds, so the store having anything in it ends the matter here.
        //
        // It also has to be the store rather than "is anything sealed": a user
        // who has a passcode set but is mid-way through enabling it has both
        // forms on disk, and one who has never set one has neither, so
        // emptiness is the only thing that distinguishes a new container.
        guard isStoreEmpty else {
            defaults.set(true, forKey: Self.markerKey)
            return
        }

        // A first-ever install inherits nothing, and clearing nothing still
        // costs three Keychain deletes and their read-backs. Someone who never
        // sets a passcode must see no launch-time Keychain mutation at all, so
        // confirmed absence ends it here — the marker is `UserDefaults`, which
        // the acceptance test does not speak about.
        guard hasInheritedKeyMaterial() else {
            defaults.set(true, forKey: Self.markerKey)
            return
        }

        do {
            try clearInheritedKeyMaterial()
            defaults.set(true, forKey: Self.markerKey)
        } catch {
            // The marker is deliberately left unset so the next launch tries
            // again. Until it succeeds, `restoreLockModeIfKeyIsWrapped` is what
            // keeps the app reachable rather than silently unusable.
            logger.error("Could not clear inherited key material: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether any passcode artifact might have been inherited.
    ///
    /// Only a **confirmed** absence counts as "nothing here". `.unavailable`
    /// means the item may well be present, and a read failure that skipped the
    /// clear would also set the marker — making the skip permanent, and leaving
    /// exactly the inherited-passcode state this type exists to remove.
    private func hasInheritedKeyMaterial() -> Bool {
        if case .absent = keyStore.loadDataKey(),
           case .absent = keyStore.loadWrappedDataKey(),
           case .absent = keychain.getPasscodeAttemptState() {
            return false
        }
        return true
    }

    /// Only ever reached with an empty store, so none of what it removes can be
    /// guarding anything: an empty store holds no sealed share, and the shares
    /// the previous install's key opened went with the store itself.
    private func clearInheritedKeyMaterial() throws {
        logger.info("New app container over surviving Keychain state — clearing inherited key material")

        try keyStore.deleteDataKey()
        try keyStore.deleteWrappedDataKey()

        // The attempt limiter keeps its state in the Keychain on purpose, so a
        // lockout cannot be shaken off by reinstalling. That reasoning does not
        // reach this path: the passcode being throttled has just been removed
        // along with the data it protected, so keeping the counter would only
        // start a new install inside a lockout guarding nothing.
        keychain.setPasscodeAttemptState(nil)
        // A confirmed absence, not merely an unreadable one: the marker is set
        // on success, so "probably gone" would never be revisited.
        guard case .absent = keychain.getPasscodeAttemptState() else {
            throw ReconcileError.clearFailed(item: "passcodeAttemptState")
        }

        // `lastMigratedVersion` is deliberately left alone. It is Keychain-held
        // so it survives reinstalls, and clearing it would re-run every ordinary
        // migration on a container that has no passcode artifact of any kind —
        // a launch-time write for people who never touched this feature, which
        // is exactly what must not happen.
    }

    // MARK: - Lock mode

    /// A wrapped data key with no clear copy means a passcode is set, whatever
    /// `UserDefaults` happens to say. Without this the app can hold key material
    /// it has no way to ask for.
    ///
    /// Each read fails closed in its own direction, and they are not the same
    /// direction:
    ///
    /// - the **wrapped** key must be *confirmed present*. Restoring the passcode
    ///   mode on an unreadable read would put up a gate with no wrapper behind
    ///   it, and `unlock` has nothing to verify against — a lock screen that can
    ///   never open.
    /// - the **clear** key must be *confirmed present* to suppress restoration.
    ///   An unreadable clear key is not a reason to leave key material
    ///   undefended, so it does not suppress anything.
    private func restoreLockModeIfKeyIsWrapped() {
        guard case .present = keyStore.loadWrappedDataKey() else { return }
        guard !isClearDataKeyPresent() else { return }
        guard lockService.mode != .passcode else { return }

        logger.warning("A wrapped data key exists but the lock mode was \(lockService.mode.rawValue, privacy: .public); restoring passcode mode")
        lockService.mode = .passcode
    }

    private func isClearDataKeyPresent() -> Bool {
        if case .present = keyStore.loadDataKey() { return true }
        return false
    }
}
