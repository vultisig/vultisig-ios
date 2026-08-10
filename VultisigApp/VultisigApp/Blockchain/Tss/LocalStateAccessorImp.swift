//
//  LocalStateAccessorImp.swift
//  VultisigApp
//

import Foundation
import OSLog
import Tss

private let logger = Log.tss.store

final class LocalStateAccessorImpl: NSObject, TssLocalStateAccessorProtocol {
    struct RuntimeError: LocalizedError {
        let description: String
        init(_ description: String) {
            self.description = description
        }

        var errorDescription: String? {
            self.description
        }
    }

    private let sharesLock = NSLock()
    private var storedKeyshares = [KeyShare]()

    /// Everything the TSS layer has handed over so far.
    ///
    /// Lock-guarded rather than `@Published` and appended on the main queue: the
    /// append has to happen inside the same write lease that sealed the value,
    /// and a queue hop would put it outside. Nothing observes this object, so
    /// there is no publisher to keep.
    var keyshares: [KeyShare] {
        sharesLock.lock()
        defer { sharesLock.unlock() }
        return storedKeyshares
    }

    /// The vault's stored key-share values, keyed by public key, copied out of
    /// the `@Model` once on the MainActor before the ceremony starts.
    ///
    /// `getLocalState` is a synchronous callback the TSS binding makes on
    /// whichever thread entered it — in this app always a
    /// `Task.detached(priority: .high)` worker, never main. Reading a SwiftData
    /// `@Model` from there is undefined behaviour, and undefined behaviour that
    /// happens to work is the worst kind here: it can hold for years and then
    /// hand back a torn value on a build with a different scheduler.
    ///
    /// Values are kept **as stored** — sealed if a passcode is set, plaintext
    /// otherwise — and opened per read rather than at construction, so no
    /// plaintext key material is parked in memory for the length of a ceremony,
    /// and a share that was sealed when the snapshot was taken stays unreadable
    /// once the key is gone.
    ///
    /// What the snapshot does change is a share whose stored *representation*
    /// moves while a ceremony is live — which only a passcode transition or the
    /// resume sweep does. Keygen and reshare are excluded from that by their
    /// episode lease; keysign holds no lease, and there the two directions are
    /// not symmetric:
    ///
    /// - snapshot plaintext, store then sealed: a later lock no longer stops
    ///   this read, where re-reading the model would have. The value is already
    ///   in this process's memory and only a ceremony this app is itself driving
    ///   can ask for it again, so this is recorded rather than closed;
    /// - snapshot sealed, store then unsealed by a disable: this read fails
    ///   closed where re-reading would have succeeded, so the ceremony fails
    ///   visibly and the user retries.
    private let vaultShares: [String: String]
    private let protector: KeyshareProtecting

    /// Snapshots the vault on the MainActor.
    ///
    /// `@MainActor` is the forcing function: it is what stops a future caller
    /// re-introducing the off-MainActor `@Model` read by constructing this from
    /// inside the ceremony instead of ahead of it. Both call sites — the GG20
    /// keygen and the GG20 keysign view models — are already main-actor bound.
    @MainActor
    convenience init(vault: Vault, protector: KeyshareProtecting = KeyshareProtector.shared) {
        // `first` wins on a duplicate public key, matching the `first(where:)`
        // the vault accessor used to do.
        let shares = Dictionary(
            vault.keyshares.map { ($0.pubkey, $0.keyshare) },
            uniquingKeysWith: { first, _ in first }
        )
        self.init(vaultShares: shares, protector: protector)
    }

    /// Private on purpose: a module-visible dictionary initializer would let a
    /// caller read `vault.keyshares` off the MainActor themselves and hand the
    /// result in, which is the exact thing the main-actor initializer exists to
    /// stop. Every construction — production and test — goes through
    /// `init(vault:)`.
    private init(vaultShares: [String: String], protector: KeyshareProtecting) {
        self.vaultShares = vaultShares
        self.protector = protector
        super.init()
    }

    func getLocalState(_ pubKey: String?, error: NSErrorPointer) -> String {
        guard let pubKey, let stored = vaultShares[pubKey] else {
            return ""
        }

        do {
            return try protector.open(stored)
        } catch let openError {
            // Only reachable once shares are stored sealed: the share exists but
            // cannot be opened. Reported through the error pointer so the TSS
            // layer sees a locked app rather than a vault missing its share —
            // the two need different handling and both used to look like "".
            logger.error("Failed to read local state: \(String(describing: openError), privacy: .public)")
            error?.pointee = openError as NSError
            return ""
        }
    }

    func saveLocalState(_ pubkey: String?, localState: String?) throws {
        guard let pubkey else {
            throw RuntimeError("pubkey is nil")
        }
        guard let localState else {
            throw RuntimeError("localstate is nil")
        }
        // Sealed here rather than where `keyshares` is copied onto the vault, so
        // a share is protected from the moment the TSS layer hands it over.
        //
        // Seal and record are one span: a passcode transition landing between
        // them could delete the wrapped key after this value was sealed under
        // it, leaving a share nothing can ever open. The lease is what makes
        // that unreachable rather than merely unlikely — and it has to be taken
        // synchronously, because this is a callback the TSS layer makes from an
        // arbitrary thread and cannot await.
        try KeyshareWriteCoordinator.shared.withWriteLease {
            let share = try KeyShare.sealed(pubkey: pubkey, keyshare: localState, protector: protector)
            sharesLock.lock()
            storedKeyshares.append(share)
            sharesLock.unlock()
        }
    }
}
