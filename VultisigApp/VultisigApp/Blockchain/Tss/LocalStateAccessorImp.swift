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
    /// otherwise — and opened per call, so the snapshot never extends the
    /// lifetime of plaintext key material and a `lock()` mid-ceremony still
    /// makes a sealed share unreadable, exactly as before.
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

    init(vaultShares: [String: String], protector: KeyshareProtecting = KeyshareProtector.shared) {
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
