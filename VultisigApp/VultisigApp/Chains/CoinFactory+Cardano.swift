//
//  CoinFactory+Cardano.swift
//  VultisigApp
//
//  Created by Assistant
//

import Foundation
import WalletCore
import CryptoKit

extension CoinFactory {

    /// Creates a proper Cardano V2 extended key structure (128 bytes total)
    static func createCardanoExtendedKey(spendingKeyHex: String, chainCodeHex: String) throws -> Data {
        guard let spendingKeyData = Data(hexString: spendingKeyHex) else {
            throw Errors.invalidPublicKey(pubKey: "public key \(spendingKeyHex) is invalid")
        }
        guard let chainCodeData = Data(hexString: chainCodeHex) else {
            throw Errors.invalidPublicKey(pubKey: "chain code \(chainCodeHex) is invalid")
        }

        // Ensure we have 32-byte keys
        guard spendingKeyData.count == 32 else {
            throw Errors.invalidPublicKey(pubKey: "spending key must be 32 bytes, got \(spendingKeyData.count)")
        }
        guard chainCodeData.count == 32 else {
            throw Errors.invalidPublicKey(pubKey: "chain code must be 32 bytes, got \(chainCodeData.count)")
        }

        // Build 128-byte extended key following Cardano V2 specification
        var extendedKeyData = Data()
        extendedKeyData.append(spendingKeyData)     // 32 bytes: EdDSA spending key
        extendedKeyData.append(spendingKeyData)     // 32 bytes: EdDSA staking key (reuse spending key)
        extendedKeyData.append(chainCodeData)       // 32 bytes: Chain code
        extendedKeyData.append(chainCodeData)       // 32 bytes: Additional chain code

        // Verify we have correct 128-byte structure
        guard extendedKeyData.count == 128 else {
            throw Errors.invalidPublicKey(pubKey: "extended key must be 128 bytes, got \(extendedKeyData.count)")
        }

        return extendedKeyData
    }

    /// Creates a Cardano Enterprise address from a spending key
    /// Enterprise addresses only contain the spending key hash, no staking component
    /// Uses WalletCore's proper Blake2b hashing for deterministic results
    static func createCardanoEnterpriseAddress(spendingKeyHex: String) throws -> String {
        guard let spendingKeyData = Data(hexString: spendingKeyHex) else {
            throw Errors.invalidPublicKey(pubKey: "spending key \(spendingKeyHex) is invalid")
        }

        guard spendingKeyData.count == 32 else {
            throw Errors.invalidPublicKey(pubKey: "spending key must be 32 bytes, got \(spendingKeyData.count)")
        }

        // Use WalletCore's proper Blake2b hash (same as used in Sui and Polkadot)
        let hash = Hash.blake2b(data: spendingKeyData, size: 28)

        // Create Enterprise address data: first byte (0x61) + 28-byte hash
        // 0x61 = (Kind_Enterprise << 4) + Network_Production = (6 << 4) + 1 = 0x61
        var addressData = Data()
        addressData.append(0x61) // Enterprise address on Production network
        addressData.append(hash)

        // Convert to bech32 format with "addr" prefix using WalletCore
        return Bech32.encode(hrp: "addr", data: addressData)
    }
}
