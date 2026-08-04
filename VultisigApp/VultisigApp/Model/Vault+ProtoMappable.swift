//
//  Vault+ProtoMappable.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation
import VultisigCommonData
import SwiftProtobuf

/// Deliberately not a `ProtoMappable` conformance.
///
/// `ProtoMappable.mapToProtobuff()` cannot throw, and a vault's key shares have
/// to be opened before they can be written into a `.vult` backup. A
/// non-throwing mapper could only swallow that failure and export ciphertext,
/// which would produce a backup that looks fine and restores to nothing. Vault
/// is never serialized through `ProtoSerializer` generically, so dropping the
/// conformance costs nothing and removes the trap.
extension Vault {
    convenience init(proto: VSVault, protector: KeyshareProtecting = KeyshareProtector.shared) throws {
        self.init(name: proto.name)
        self.pubKeyECDSA = proto.publicKeyEcdsa
        self.pubKeyEdDSA = proto.publicKeyEddsa
        self.signers = proto.signers
        self.hexChainCode = proto.hexChainCode
        // Shares arrive from the backup in the clear and are sealed on the way
        // into storage, so an imported vault ends up in exactly the protection
        // state the store is already in — sealed with a passcode set, plaintext
        // without one.
        self.keyshares = try proto.keyShares.map {
            KeyShare(pubkey: $0.publicKey, keyshare: try protector.seal($0.keyshare))
        }
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
        self.publicKeyMLDSA44 = proto.publicKeyMldsa44.nilIfEmpty
    }

    /// - Throws: `KeyshareProtectionError.locked` when a share cannot be opened,
    ///   so a backup is never written with unreadable key material in it.
    func mapToProtobuff(protector: KeyshareProtecting = KeyshareProtector.shared) throws -> VSVault {
        let openedKeyShares: [VSVault.KeyShare] = try keyshares.map { share in
            var proto = VSVault.KeyShare()
            proto.publicKey = share.pubkey
            proto.keyshare = try protector.open(share.keyshare)
            return proto
        }

        return VSVault.with {
            $0.name = name
            $0.publicKeyEcdsa = pubKeyECDSA
            $0.publicKeyEddsa = pubKeyEdDSA
            $0.publicKeyMldsa44 = publicKeyMLDSA44 ?? ""
            $0.signers = signers
            $0.hexChainCode = hexChainCode
            $0.localPartyID = self.localPartyID
            $0.resharePrefix = self.resharePrefix ?? ""
            $0.libType = libType?.toVSLibType() ?? .gg20
            $0.keyShares = openedKeyShares
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
