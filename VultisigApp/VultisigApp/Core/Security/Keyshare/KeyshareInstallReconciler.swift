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
    private let biometrics: BiometricUnlockStore
    private let lockService: AppLockService
    private let coordinator: KeyshareWriteCoordinator
    private let sweeper: KeyshareSweeping
    private let defaults: UserDefaults

    init(
        keychain: KeychainService = DefaultKeychainService.shared,
        keyStore: KeyshareKeyStoring = DefaultKeyshareKeyStore.shared,
        biometrics: BiometricUnlockStore = .shared,
        lockService: AppLockService = .shared,
        coordinator: KeyshareWriteCoordinator = .shared,
        sweeper: KeyshareSweeping = KeyshareSweeper.shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.keyStore = keyStore
        self.biometrics = biometrics
        self.lockService = lockService
        self.coordinator = coordinator
        self.sweeper = sweeper
        self.defaults = defaults
    }

    /// What the container's store says about whether it is new.
    ///
    /// Three cases and not a `Bool`, because "I could not read the store" is
    /// neither of the other two and every way of pretending otherwise is wrong:
    /// read as *occupied* it retires the clear permanently on a container that
    /// may well be new, and read as *empty* it would delete key material a full
    /// store still depends on.
    enum StoreOccupancy {
        case empty
        case occupied
        case unknown
    }

    /// Whether the store holds a key share that is sealed.
    ///
    /// Three cases for the same reason ``StoreOccupancy`` has three: the answer
    /// licenses a *state*, and "the store could not be read" is neither of the
    /// other two. Read as `.sealed` it would raise a recovery screen over a
    /// perfectly healthy install; read as `.nothingSealed` it would let the
    /// orphaned state carry on opening silently.
    ///
    /// Named `nothingSealed` rather than `none` so it cannot be read as
    /// `Optional`'s case at a call site — the same reason
    /// ``InheritedKeyMaterial`` avoids `none`/`some`.
    enum SealedShareCensus {
        case sealed
        case nothingSealed
        case unknown
    }

    /// What reconciliation found that somebody above it has to act on.
    ///
    /// Only one thing so far, and it is deliberately not expressed as a `Bool`:
    /// the compiler points at every call site when another is added, which is
    /// the forcing function this feature prefers.
    enum Outcome: Equatable {
        /// Nothing for the app to raise.
        case nothing
        /// The store holds at least one sealed key share and the key that opens
        /// it is **confirmed** gone. Nothing on this device can read those
        /// shares again, so the app must say so rather than open over them.
        case sealedSharesWithoutTheirKey
    }

    @MainActor
    @discardableResult
    func reconcile() -> Outcome {
        // Both are computed here, on the main actor, and handed down as values.
        // `Vault` is a main-actor-only `@Model` and the work below is not
        // isolated, so the alternative would be isolating the whole type — see
        // `storeOccupancy()`, which has solved this once already.
        reconcile(occupancy: storeOccupancy(), census: sealedShareCensus())
    }

    @MainActor
    private func storeOccupancy() -> StoreOccupancy {
        guard let context = Storage.shared.modelContext,
              let count = try? context.fetchCount(FetchDescriptor<Vault>()) else {
            return .unknown
        }
        return count == 0 ? .empty : .occupied
    }

    /// Safe to ask here: it takes no lease of its own, needs no data key —
    /// `isSealed` is a prefix check — and the model context is installed before
    /// `VultisigApp.init()` runs this.
    ///
    /// It refuses a context carrying unsaved work, which at launch it never is.
    /// That refusal is `.unknown`, not an error to report: a census that cannot
    /// be taken decides nothing, and the condition does not depend on the lock
    /// mode, so the next launch that can read the store still finds it.
    @MainActor
    private func sealedShareCensus() -> SealedShareCensus {
        do {
            return try sweeper.hasSealedShare() ? .sealed : .nothingSealed
        } catch {
            logger.info("The sealed-share census could not be taken: \(String(describing: error), privacy: .public)")
            return .unknown
        }
    }

    /// - Parameter census: defaults to `.unknown`, which is the answer that
    ///   changes nothing — a caller that cannot take the census must not be
    ///   able to assert either of the other two by omission.
    @discardableResult
    func reconcile(isStoreEmpty: Bool, census: SealedShareCensus = .unknown) -> Outcome {
        reconcile(occupancy: isStoreEmpty ? .empty : .occupied, census: census)
    }

    /// - Parameter census: see ``reconcile(isStoreEmpty:census:)``.
    @discardableResult
    func reconcile(occupancy: StoreOccupancy, census: SealedShareCensus = .unknown) -> Outcome {
        // Both halves read the wrapped key and act on what they read, so both
        // have to be indivisible against a passcode transition. Without this a
        // launch could clear a wrapper `setPasscode` had just made durable, or
        // decide the lock mode from a snapshot a concurrent disable has already
        // invalidated.
        guard let lease = try? coordinator.beginTransition() else {
            logger.info("Reconciliation skipped: a passcode transition or key-share write is in progress")
            return .nothing
        }
        defer { coordinator.end(lease) }

        clearInheritedKeyMaterialIfContainerIsNew(occupancy: occupancy)
        return alignLockModeWithTheWrappedKey(census: census)
    }

    // MARK: - Inherited key material

    private func clearInheritedKeyMaterialIfContainerIsNew(occupancy: StoreOccupancy) {
        guard !defaults.bool(forKey: Self.markerKey) else { return }

        switch occupancy {
        case .occupied:
            // Existing users reach this line exactly once, on the first launch
            // of the build that introduces the marker — with a full store.
            // Clearing their wrapped key would orphan every sealed share, which
            // in this app is lost funds, so the store having anything in it ends
            // the matter here.
            //
            // It also has to be the store rather than "is anything sealed": a
            // user part-way through enabling a passcode has a wrapper and
            // unsealed shares, and one who has never set one has neither, so
            // emptiness is the only thing that distinguishes a new container.
            defaults.set(true, forKey: Self.markerKey)
            return
        case .unknown:
            // The marker is permanent, so it must never be written on a guess.
            // Setting it here would retire the clear for good on a container
            // that may be new — and a new container that keeps the previous
            // install's wrapped key is a passcode gate the user cannot open and
            // cannot get rid of by reinstalling, which is the whole reason this
            // type exists. A deferred launch costs nothing.
            logger.info("Reconciliation deferred: the vault store could not be read")
            return
        case .empty:
            break
        }

        switch inheritedKeyMaterial() {
        case .nothing:
            // A first-ever install inherits nothing, and clearing nothing still
            // costs a Keychain delete and its read-back per item. Someone who
            // never sets a passcode must see no launch-time Keychain mutation at
            // all, so confirmed absence ends it here — the marker is
            // `UserDefaults`, which the acceptance test does not speak about.
            defaults.set(true, forKey: Self.markerKey)
            return
        case .unknown:
            // Same rule, and this is the case that keeps the acceptance test
            // absolute rather than merely usual: issuing deletes over reads that
            // failed is a launch-time Keychain mutation for someone who has
            // never touched this feature. Deferring writes nothing at all and
            // the next launch decides with an answer.
            logger.info("Reconciliation deferred: inherited key material could not be determined")
            return
        case .something:
            break
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

    /// What, if anything, this container inherited.
    ///
    /// Three cases for the same reason the store's is: only a **confirmed**
    /// absence means "nothing here", and an unreadable item is neither that nor
    /// evidence of something. Collapsing `.unknown` into `.some` would issue
    /// deletes on a first-ever install whose Keychain answered badly for a
    /// moment; collapsing it into `.none` would set the marker and make the skip
    /// permanent, leaving exactly the inherited-passcode state this type exists
    /// to remove.
    enum InheritedKeyMaterial {
        /// Named `nothing`/`something` rather than `none`/`some` so neither can
        /// be read as `Optional`'s cases at a call site.
        case nothing
        case something
        case unknown
    }

    private func inheritedKeyMaterial() -> InheritedKeyMaterial {
        let wrapper = keyStore.loadWrappedDataKey()
        let attempts = keychain.getPasscodeAttemptState()

        if case .present = wrapper { return .something }
        if case .present = attempts { return .something }
        // The biometric copy has no tri-state to report — presence is checked
        // without authentication and answers true even when the item exists but
        // needs a face, so a `false` here is as close to a confirmed absence as
        // this item gets.
        if biometrics.isEnabled { return .something }
        if case .unavailable = wrapper { return .unknown }
        if case .unavailable = attempts { return .unknown }
        return .nothing
    }

    /// Only ever reached with an empty store, so none of what it removes can be
    /// guarding anything: an empty store holds no sealed share, and the shares
    /// the previous install's key opened went with the store itself.
    private func clearInheritedKeyMaterial() throws {
        logger.info("New app container over surviving Keychain state — clearing inherited key material")

        try keyStore.deleteWrappedDataKey()

        // The biometric copy is a second copy of the same key and survives the
        // uninstall too. Left behind it reports biometric unlock as already
        // enabled — an enablement nobody made on this install — and it is bound
        // to a wrapper that has just been deleted, so it could only ever be
        // refused. Deletion tolerates a missing item, so this is a no-op on a
        // first-ever install, and it is verified rather than fire-and-forget:
        // a survivor is exactly the silent-shortcut case `disable()` exists to
        // prevent.
        try biometrics.disable()

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
    ///
    /// A confirmed-absent wrapper over a store that still holds a **sealed**
    /// share is a third thing, and it is not a lock-mode problem at all: the
    /// shares are ciphertext whose key is gone, so no mode repair makes them
    /// readable. It is reported instead, and the mode is left exactly as it is —
    /// there is nothing to repair, and moving it would erase the only remaining
    /// evidence that a passcode was ever set here.
    ///
    /// The condition deliberately does **not** consult the lock mode. Anyone who
    /// already hit this has `.deviceAuth` persisted, because this method wrote
    /// it on their first launch; a check gated on `.passcode` would miss exactly
    /// the installs that need reporting.
    private func alignLockModeWithTheWrappedKey(census: SealedShareCensus) -> Outcome {
        switch keyStore.loadWrappedDataKey() {
        case .present:
            guard lockService.mode != .passcode else { return .nothing }
            logger.warning("A wrapped data key exists but the lock mode was \(lockService.mode.rawValue, privacy: .public); restoring passcode mode")
            lockService.mode = .passcode
            return .nothing
        case .absent:
            if case .sealed = census {
                logger.error("Sealed key shares with no wrapped data key to open them; this device cannot sign with them")
                return .sealedSharesWithoutTheirKey
            }
            // `.unknown` keeps the repair rather than deferring it, and that is
            // the safe side here: a persisted `.passcode` over an absent wrapper
            // is a gate no passcode can open, which is the lockout this branch
            // exists to prevent. Nothing is lost by repairing — the report above
            // does not depend on the mode, so the next launch that can read the
            // store still makes it.
            guard lockService.mode == .passcode else { return .nothing }
            logger.warning("The lock mode was passcode with no wrapped data key behind it; falling back to device auth")
            lockService.mode = .deviceAuth
            return .nothing
        case .unavailable:
            return .nothing
        }
    }
}
