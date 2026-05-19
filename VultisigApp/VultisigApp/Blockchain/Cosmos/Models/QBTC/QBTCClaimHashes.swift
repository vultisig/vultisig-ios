//
//  QBTCClaimHashes.swift
//  VultisigApp
//
//  Domain-separated hash construction for the QBTC claim flow.
//  Mirrors `vultisig-sdk/.../computeClaimHashes.ts` byte-for-byte.
//  Tags MUST match `x/qbtc/zk/message.go` server-side.
//

import Foundation
import WalletCore

struct QBTCClaimHashes {
    let messageHash: Data
    let addressHash: Data
    let qbtcAddressHash: Data
    let circuit: BtcClaimCircuit
}

enum QBTCClaimHashError: LocalizedError {
    case invalidCompressedPubkey
    case schnorrNotSupported
    case invalidHashLength(field: String, expected: Int, got: Int)
    case invalidUtf8(String)

    var errorDescription: String? {
        switch self {
        case .invalidCompressedPubkey:
            return "compressedPubkey must be a 33-byte compressed secp256k1 key (first byte 0x02 or 0x03)"
        case .schnorrNotSupported:
            return "Schnorr / Taproot claim circuit is not yet supported on the QBTC chain"
        case .invalidHashLength(let field, let expected, let got):
            return "\(field) must be \(expected) bytes, got \(got)"
        case .invalidUtf8(let value):
            return "Could not encode value as UTF-8: \(value)"
        }
    }
}

extension QBTCClaimHashes {
    /// Hash160 = RIPEMD160(SHA256(data)) — the standard Bitcoin hash.
    static func hash160(_ data: Data) -> Data {
        Hash.ripemd(data: Hash.sha256(data: data))
    }

    /// Computes the address hash for QBTC claiming.
    /// - ECDSA circuit: Hash160(compressedPubkey) — 20 bytes.
    /// - Schnorr circuit: x-only pubkey (last 32 bytes of 33-byte compressed key).
    static func computeAddressHash(compressedPubkey: Data, circuit: BtcClaimCircuit) throws -> Data {
        guard compressedPubkey.count == 33,
              compressedPubkey[0] == 0x02 || compressedPubkey[0] == 0x03 else {
            throw QBTCClaimHashError.invalidCompressedPubkey
        }

        switch circuit {
        case .schnorr:
            return compressedPubkey.subdata(in: 1..<33)
        case .ecdsa:
            return hash160(compressedPubkey)
        }
    }

    /// SHA-256 of the QBTC bech32 address string (UTF-8 bytes). 32 bytes.
    static func computeQbtcAddressHash(_ qbtcAddress: String) throws -> Data {
        guard let bytes = qbtcAddress.data(using: .utf8) else {
            throw QBTCClaimHashError.invalidUtf8(qbtcAddress)
        }
        return Hash.sha256(data: bytes)
    }

    /// First 8 bytes of SHA-256 of the chain ID. Truncation, not full digest.
    static func computeChainIdHash(_ chainId: String) throws -> Data {
        guard let bytes = chainId.data(using: .utf8) else {
            throw QBTCClaimHashError.invalidUtf8(chainId)
        }
        let full = Hash.sha256(data: bytes)
        return full.prefix(QBTCClaimConfig.chainIdHashPrefixBytes)
    }

    /// Final claim message hash:
    /// `SHA256("ecdsa-hash160:" || addressHash || qbtcAddressHash || chainIdHash || "qbtc-claim-v1")`
    /// Throws on Schnorr — the chain has not defined a Schnorr tag yet (btcq-org/qbtc#148).
    static func computeClaimMessageHash(
        addressHash: Data,
        qbtcAddressHash: Data,
        chainIdHash: Data,
        circuit: BtcClaimCircuit
    ) throws -> Data {
        if circuit == .schnorr {
            throw QBTCClaimHashError.schnorrNotSupported
        }

        guard addressHash.count == 20 else {
            throw QBTCClaimHashError.invalidHashLength(field: "addressHash", expected: 20, got: addressHash.count)
        }
        guard qbtcAddressHash.count == 32 else {
            throw QBTCClaimHashError.invalidHashLength(field: "qbtcAddressHash", expected: 32, got: qbtcAddressHash.count)
        }
        guard chainIdHash.count == 8 else {
            throw QBTCClaimHashError.invalidHashLength(field: "chainIdHash", expected: 8, got: chainIdHash.count)
        }

        guard let prefix = QBTCClaimConfig.domainTagPrefix.data(using: .utf8),
              let suffix = QBTCClaimConfig.domainTagSuffix.data(using: .utf8) else {
            throw QBTCClaimHashError.invalidUtf8("domain-separation tags")
        }

        var message = Data()
        message.reserveCapacity(prefix.count + 20 + 32 + 8 + suffix.count)
        message.append(prefix)
        message.append(addressHash)
        message.append(qbtcAddressHash)
        message.append(chainIdHash)
        message.append(suffix)

        return Hash.sha256(data: message)
    }

    /// Convenience wrapper that computes all hashes needed for a QBTC claim.
    static func computeAll(
        btcAddress: String,
        compressedPubkey: Data,
        qbtcAddress: String,
        chainId: String
    ) throws -> QBTCClaimHashes {
        let addressType = try BtcAddressType.detect(btcAddress)
        let circuit = addressType.circuit

        let addressHash = try computeAddressHash(compressedPubkey: compressedPubkey, circuit: circuit)
        let qbtcAddressHash = try computeQbtcAddressHash(qbtcAddress)
        let chainIdHash = try computeChainIdHash(chainId)

        let messageHash = try computeClaimMessageHash(
            addressHash: addressHash,
            qbtcAddressHash: qbtcAddressHash,
            chainIdHash: chainIdHash,
            circuit: circuit
        )

        return QBTCClaimHashes(
            messageHash: messageHash,
            addressHash: addressHash,
            qbtcAddressHash: qbtcAddressHash,
            circuit: circuit
        )
    }
}
