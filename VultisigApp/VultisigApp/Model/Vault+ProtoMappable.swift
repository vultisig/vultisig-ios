//
//  Vault+ProtoMappable.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation
import VultisigCommonData
import SwiftProtobuf

extension Vault: ProtoMappable {
    convenience init(proto: VSVault) throws {
        self.init(name: proto.name)
        self.pubKeyECDSA = proto.publicKeyEcdsa
        self.pubKeyEdDSA = proto.publicKeyEddsa
        self.signers = proto.signers
        self.hexChainCode = proto.hexChainCode
        self.keyshares = proto.keyShares.map { KeyShare(pubkey: $0.publicKey, keyshare: $0.keyshare) }
        self.localPartyID = proto.localPartyID
        self.resharePrefix = proto.resharePrefix
        let timeInterval = TimeInterval(proto.createdAt.seconds) + TimeInterval(proto.createdAt.nanos) / 1_000_000_000
        self.createdAt = Date(timeIntervalSince1970: timeInterval)
        self.order = 0
        self.isBackedUp = true
        self.libType = proto.libType.toLibType()
        self.chainPublicKeys = try proto.chainPublicKeys.map {
            guard let chain = Chain(name: $0.chain) else {
                throw HelperError.runtimeError("Invalid chain name in proto: \($0.chain)")
            }
            return ChainPublicKey(
                chain: chain,
                publicKeyHex: $0.publicKey,
                isEddsa: $0.isEddsa
            )
        }
    }

    func mapToProtobuff() -> VSVault {
        return VSVault.with {
            $0.name = name
            $0.publicKeyEcdsa = pubKeyECDSA
            $0.publicKeyEddsa = pubKeyEdDSA
            $0.signers = signers
            $0.hexChainCode = hexChainCode
            $0.localPartyID = self.localPartyID
            $0.resharePrefix = self.resharePrefix ?? ""
            $0.libType = libType?.toVSLibType() ?? .gg20
            $0.keyShares = self.keyshares.map { s in
                var share = VSVault.KeyShare()
                share.publicKey = s.pubkey
                share.keyshare = s.keyshare
                return share
            }
            $0.createdAt = Google_Protobuf_Timestamp(date: self.createdAt)
            $0.chainPublicKeys = self.chainPublicKeys.map { c in
                var cp = VSVault.ChainPublicKey()
                cp.publicKey = c.publicKeyHex
                cp.chain = c.chain.name
                cp.isEddsa = c.isEddsa
                return cp
            }
        }
    }
}
