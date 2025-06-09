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
        
        // Convert to bech32 format with "addr" prefix
        let bech32Address = try encodeBech32(data: addressData, hrp: "addr")
        
        return bech32Address
    }
    
    /// Encode data as bech32 format
    private static func encodeBech32(data: Data, hrp: String) throws -> String {
        // Convert 8-bit data to 5-bit groups for bech32
        var converted = [UInt8]()
        var acc = 0
        var bits = 0
        
        for byte in data {
            acc = (acc << 8) | Int(byte)
            bits += 8
            
            while bits >= 5 {
                bits -= 5
                converted.append(UInt8((acc >> bits) & 31))
            }
        }
        
        if bits > 0 {
            converted.append(UInt8((acc << (5 - bits)) & 31))
        }
        
        // Generate bech32 checksum
        let checksum = bech32Checksum(hrp: hrp, data: converted)
        let fullData = converted + checksum
        
        // Convert to bech32 characters
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        let encoded = fullData.map { charset[charset.index(charset.startIndex, offsetBy: Int($0))] }
        
        return hrp + "1" + String(encoded)
    }
    
    /// Generate bech32 checksum
    private static func bech32Checksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp: hrp) + data
        let polymod = bech32Polymod(values + [0, 0, 0, 0, 0, 0]) ^ 1
        return (0..<6).map { UInt8((polymod >> (5 * (5 - $0))) & 31) }
    }
    
    /// Expand HRP for bech32
    private static func hrpExpand(hrp: String) -> [UInt8] {
        let high = hrp.map { UInt8($0.asciiValue! >> 5) }
        let low = hrp.map { UInt8($0.asciiValue! & 31) }
        return high + [0] + low
    }
    
    /// Bech32 polymod function
    private static func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        
        for value in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(value)
            for i in 0..<5 {
                if (top >> i) & 1 == 1 {
                    chk ^= generator[i]
                }
            }
        }
        
        return chk
    }
} 