//
//  LocalStateAccessorImp.swift
//  VultisigApp
//

import Foundation
import OSLog
import Tss

private let logger = Log.tss.store

final class LocalStateAccessorImpl: NSObject, TssLocalStateAccessorProtocol, ObservableObject {
    struct RuntimeError: LocalizedError {
        let description: String
        init(_ description: String) {
            self.description = description
        }

        var errorDescription: String? {
            self.description
        }
    }

    @Published var keyshares = [KeyShare]()
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
        let share = try KeyShare.sealed(pubkey: pubkey, keyshare: localState)
        DispatchQueue.main.async {
            self.keyshares.append(share)
        }
    }
}
