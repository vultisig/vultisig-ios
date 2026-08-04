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
/// it was — so a reinstall begins with no vaults and no lock mode while the
/// wrapped data key and the attempt counter both survive.
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
/// 2. **The lock mode is made to agree with the wrapped key**, in both
///    directions: a wrapper with no passcode mode means key material with no
///    door in front of it, and a passcode mode with no wrapper means a door with
///    nothing behind it — `unlock` has nothing to verify against, so it could
///    never be opened.
///
/// Runs on every launch, before migrations, and under
/// ``KeyshareWriteCoordinator``'s transition lease: it deletes and re-decides
/// exactly the state `PasscodeService` is moving during a set or a disable, and
/// a launch landing in the middle of one could delete a wrapper the set had just
/// verified — leaving the key adopted in memory with nothing on disk that wraps
/// it. If the lease cannot be taken, reconciliation is skipped entirely and the
/// container is left unmarked so the next launch tries again.
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
    private let coordinator: KeyshareWriteCoordinator
    private let defaults: UserDefaults

    init(
        keychain: KeychainService = DefaultKeychainService.shared,
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared,
        lockService: AppLockService = .shared,
        coordinator: KeyshareWriteCoordinator = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.keyStore = keyStore
        self.lockService = lockService
        self.coordinator = coordinator
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
        // Both halves read the wrapped key and act on what they read, so both
        // have to be indivisible against a passcode transition. Without this a
        // launch could clear a wrapper `setPasscode` had just made durable, or
        // decide the lock mode from a snapshot a concurrent disable has already
        // invalidated.
        guard let lease = try? coordinator.beginTransition() else {
            logger.info("Reconciliation skipped: a passcode transition or key-share write is in progress")
            return
        }
        defer { coordinator.end(lease) }

        clearInheritedKeyMaterialIfContainerIsNew(isStoreEmpty: isStoreEmpty)
        alignLockModeWithTheWrappedKey()
    }

    // MARK: - Inherited key material

    private func clearInheritedKeyMaterialIfContainerIsNew(isStoreEmpty: Bool) {
        guard !defaults.bool(forKey: Self.markerKey) else { return }

        // Existing users reach this line exactly once, on the first launch of the
        // build that introduces the marker — with a full store. Clearing their
        // wrapped key would orphan every sealed share, which in this app is lost
        // funds, so the store having anything in it ends the matter here.
        //
        // It also has to be the store rather than "is anything sealed": a user
        // part-way through enabling a passcode has a wrapper and unsealed
        // shares, and one who has never set one has neither, so emptiness is the
        // only thing that distinguishes a new container.
        guard isStoreEmpty else {
            defaults.set(true, forKey: Self.markerKey)
            return
        }

        // A first-ever install inherits nothing, and clearing nothing still
        // costs a Keychain delete and its read-back per item. Someone who never
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
            // again. Until it succeeds, the lock-mode alignment below is what
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
        if case .absent = keyStore.loadWrappedDataKey(),
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

    /// The wrapped key is the whole of the persisted passcode state, so the lock
    /// mode has to agree with it — and being wrong in either direction locks
    /// someone out or leaves key material undefended.
    ///
    /// Only a **confirmed** answer moves the mode. An unreadable Keychain leaves
    /// it exactly as it is: taking `.unavailable` for presence would raise a gate
    /// with nothing behind it, and taking it for absence would take a real gate
    /// down.
    ///
    /// Each direction repairs a different interruption:
    ///
    /// - **present ⇒ `.passcode`** covers a removal that stopped half way.
    ///   `disablePasscode` changes the mode *before* deleting the wrapper, so a
    ///   crash in between leaves plaintext shares, a surviving wrapper and a
    ///   persisted `.deviceAuth`. Putting the gate back up is what makes that
    ///   ordering safe to choose in the first place.
    /// - **absent ⇒ `.deviceAuth`** covers a wrapper that went away underneath a
    ///   persisted `.passcode` — a reinstall clear, or the crash order the
    ///   disable deliberately avoids. `unlock` has nothing to verify a passcode
    ///   against, so that gate could never be opened.
    private func alignLockModeWithTheWrappedKey() {
        switch keyStore.loadWrappedDataKey() {
        case .present:
            guard lockService.mode != .passcode else { return }
            logger.warning("A wrapped data key exists but the lock mode was \(lockService.mode.rawValue, privacy: .public); restoring passcode mode")
            lockService.mode = .passcode
        case .absent:
            guard lockService.mode == .passcode else { return }
            logger.warning("The lock mode was passcode with no wrapped data key behind it; falling back to device auth")
            lockService.mode = .deviceAuth
        case .unavailable:
            return
        }
    }
}
