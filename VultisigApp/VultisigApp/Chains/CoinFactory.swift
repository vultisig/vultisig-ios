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
        default:
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }
        
        if asset.chain == .bitcoinCash {
            address = address.replacingOccurrences(of: "bitcoincash:", with: "")
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
            
            if asset.coinType == .tron {
                return try createTronXpub(derivedKey: derivedKey, chainCode: vault.hexChainCode)
            }
            
            guard
                let pubKeyData = Data(hexString: derivedKey),
                let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyECDSA)
            }
            return publicKey
        }
    }
    
    static func createTronXpub(derivedKey: String, chainCode: String) throws -> PublicKey {
        // Convert hex strings to data
        guard
            let pubKeyData = Data(hexString: derivedKey),
            let chainCodeData = Data(hexString: chainCode) else {
            throw Errors.invalidPublicKey(pubKey: derivedKey)
        }
        
        // XPUB version for Tron (Bitcoin mainnet version is typically used)
        let version = Data([0x04, 0x88, 0xB2, 0x1E])
        
        // Depth (master key = 0)
        let depth = Data([0x00])
        
        // Parent fingerprint (for root keys, it's all zeros)
        let parentFingerprint = Data([0x00, 0x00, 0x00, 0x00])
        
        // Child number (for root keys, it's all zeros)
        let childNumber = Data([0x00, 0x00, 0x00, 0x00])
        
        // Concatenate components
        var xpubData = Data()
        xpubData.append(version)
        xpubData.append(depth)
        xpubData.append(parentFingerprint)
        xpubData.append(childNumber)
        xpubData.append(chainCodeData)
        xpubData.append(pubKeyData)
        
        // Base58Check encode the xpub
        let xpub = Base58.encode(data: xpubData)
        
        guard let publicKey = HDWallet.getPublicKeyFromExtended(extended: xpub, coin: CoinType.tron,  derivationPath: CoinType.tron.derivationPath()) else {
            throw Errors.invalidPublicKey(pubKey: xpubData.hexString)
        }
        
        return publicKey
    }
}

