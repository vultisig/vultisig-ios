//
//  AccountFactory.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.06.2024.
//

import Foundation
import WalletCore

struct CoinFactory {
    
    private init() { }
    
    static func create(asset: CoinMeta, vault: Vault) throws -> Coin {
        let publicKey = try publicKey(asset: asset, vault: vault)
        
        var address: String
        switch asset.chain {
        case .mayaChain:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
            address = anyAddress.description
        case .cardano:
            // Use default derivation instead of AnyAddress to avoid ed25519Cardano requirement
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        default:
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }
        
        if asset.chain == .bitcoinCash {
            address = address.replacingOccurrences(of: "bitcoincash:", with: "")
        }
        
        // Validate Cardano address using WalletCore's own validation
        if asset.chain == .cardano {
            guard let _ = AnyAddress(string: address, coin: .cardano) else {
                throw Errors.invalidPublicKey(pubKey: "WalletCore validation failed for Cardano address: \(address)")
            }
        }
        
        return Coin(asset: asset, address: address, hexPublicKey: publicKey.data.hexString)
    }
}

extension CoinFactory {
    
    enum Errors: Error, LocalizedError {
        case invalidPublicKey(pubKey: String)
        
        var errorDescription: String? {
            switch self {
            case .invalidPublicKey(let pubKey):
                return "Public key: \(pubKey) is invalid"
            }
        }
    }
    
    static func publicKey(asset: CoinMeta, vault: Vault) throws -> PublicKey {
        switch asset.chain.signingKeyType {
        case .EdDSA:
            
            if asset.chain == .cardano {
                // Proper Cardano key derivation using TSS-derived EdDSA key + chain code
                guard let pubKeyData = Data(hexString: vault.pubKeyEdDSA) else {
                    print("Public key: \(vault.pubKeyEdDSA) is invalid hex for ADA chain")
                    throw Errors.invalidPublicKey(pubKey: vault.pubKeyEdDSA)
                }
                
                guard let chainCodeData = Data(hexString: vault.hexChainCode) else {
                    print("Chain code: \(vault.hexChainCode) is invalid hex for ADA chain")
                    throw Errors.invalidPublicKey(pubKey: "Invalid chain code")
                }
                
                // Cardano V2 approach: Use raw EdDSA key + chain code (no derivation needed)
                // According to Cardano V2 spec: Public key is 64-byte (32-byte ED25519 + 32-byte chain code)
                
                // For Cardano, construct the 64-byte public key first (EdDSA + chain code)
                var cardano64ByteKey = Data()
                cardano64ByteKey.append(pubKeyData)    // 32 bytes: ED25519 public key
                cardano64ByteKey.append(chainCodeData) // 32 bytes: chain code
                
                // Then extend to 128 bytes for WalletCore compatibility
                // Construct proper 128-byte Cardano extended public key structure
                var cardanoExtendedKey = Data()
                cardanoExtendedKey.append(pubKeyData)    // 32 bytes: spending key (raw EdDSA)
                cardanoExtendedKey.append(pubKeyData)    // 32 bytes: staking key (same key for simplicity)
                cardanoExtendedKey.append(chainCodeData) // 32 bytes: chain code
                cardanoExtendedKey.append(chainCodeData) // 32 bytes: additional chain code
                
                // Create ed25519Cardano public key
                guard let cardanoKey = PublicKey(data: cardanoExtendedKey, type: .ed25519Cardano) else {
                    print("Failed to create ed25519Cardano key from properly structured data")
                    throw Errors.invalidPublicKey(pubKey: "Failed to create Cardano extended key")
                }
                

                return cardanoKey
            }
            
            guard
                let pubKeyData = Data(hexString: vault.pubKeyEdDSA),
                let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyEdDSA)
            }
            return publicKey
            
        case .ECDSA:
            let derivedKey = PublicKeyHelper.getDerivedPubKey(
                hexPubKey: vault.pubKeyECDSA,
                hexChainCode: vault.hexChainCode,
                derivePath: asset.coinType.derivationPath()
            )
            
            guard
                let pubKeyData = Data(hexString: derivedKey),
                let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyECDSA)
            }
            
            if asset.coinType == .tron {
                return publicKey.uncompressed
            }
            
            return publicKey
        }
    }
    
}

