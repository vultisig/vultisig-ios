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

        let address: String
        switch asset.chain {
        case .mayaChain:
            let anyAddress = AnyAddress(publicKey: publicKey, coin: .thorchain, hrp: "maya")
            address = anyAddress.description
        default:
            address = asset.coinType.deriveAddressFromPublicKey(publicKey: publicKey)
        }

        return Coin(asset: asset, address: address, hexPublicKey: publicKey.data.hexString)
    }
}

private extension CoinFactory {

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
        switch asset.chain {
        case .solana, .sui, .polkadot:
            guard 
                let pubKeyData = Data(hexString: vault.pubKeyEdDSA),
                let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyEdDSA)
            }
            return publicKey

        case .arbitrum, .avalanche, .base, .bitcoin, .bitcoinCash, .blast, .bscChain, .cronosChain, .dash, .dogecoin, .dydx, .ethereum, .gaiaChain, .kujira, .litecoin, .mayaChain, .optimism, .polygon, .thorChain, .zksync:
            let derivedKey = PublicKeyHelper.getDerivedPubKey(
                hexPubKey: vault.pubKeyECDSA,
                hexChainCode: vault.hexChainCode,
                derivePath: asset.coinType.derivationPath()
            )
            guard
                let pubKeyData = Data(hexString: derivedKey),
                let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
                throw Errors.invalidPublicKey(pubKey: vault.pubKeyEdDSA)
            }
            return publicKey
        }
    }
}
