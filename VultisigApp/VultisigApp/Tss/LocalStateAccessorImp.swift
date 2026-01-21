//
//  LocalStateAccessorImp.swift
//  VultisigApp
//

import Foundation
import Tss

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
        for share in self.vault.keyshares where share.pubkey == pubKey {
            return share.keyshare
        }
        return ""
    }

    func saveLocalState(_ pubkey: String?, localState: String?) throws {
        guard let pubkey else {
            throw RuntimeError("pubkey is nil")
        }
        guard let localState else {
            throw RuntimeError("localstate is nil")
        }
        DispatchQueue.main.async {
            self.keyshares.append(KeyShare(pubkey: pubkey, keyshare: localState))
        }
    }
}
