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

    private var vault: Vault
    init(vault: Vault) {
        self.vault = vault
    }
    func getLocalState(_ pubKey: String?, error: NSErrorPointer) -> String {
        guard let pubKey else {
            return ""
        }

        do {
            return try vault.keyshareValue(for: pubKey) ?? ""
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
            let share = try KeyShare.sealed(pubkey: pubkey, keyshare: localState)
            sharesLock.lock()
            storedKeyshares.append(share)
            sharesLock.unlock()
        }
    }
}
