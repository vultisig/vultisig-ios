//
//  Vault+ProtoMappable.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation
import VultisigCommonData

extension Vault: ProtoMappable {
    convenience init(proto: VSVault) throws {
        self.init(name: proto.name)
        self.pubKeyECDSA = proto.publicKeyEcdsa
        self.pubKeyEdDSA = proto.publicKeyEddsa
        self.signers = proto.signers
        self.createdAt = Date.now
        self.hexChainCode = proto.hexChainCode
        proto.keyShares.forEach { s in
            self.keyshares.append(KeyShare(pubkey: s.publicKey, keyshare: s.keyshare))
        }
        self.localPartyID = proto.localPartyID
        self.resharePrefix = proto.resharePrefix
        self.order = 0
        self.isBackedUp = false
    }
    
    func mapToProtobuff() ->  VSVault {
        var vault =  VSVault.with {
            $0.name = name
            $0.publicKeyEcdsa = pubKeyECDSA
            $0.publicKeyEddsa = pubKeyEdDSA
            $0.signers = signers
            $0.hexChainCode = hexChainCode
            $0.localPartyID = self.localPartyID
            $0.resharePrefix = self.resharePrefix ?? ""
        }
        self.keyshares.forEach{s in
            var share = VSVault.KeyShare()
            share.publicKey = s.pubkey
            share.keyshare = s.keyshare
            vault.keyShares.append(share)
        }
        return vault
    }
}
