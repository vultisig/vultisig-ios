//
//  KeysignService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.07.2024.
//

import Foundation

struct KeysignMessageFactory {

    private let payload: KeysignPayload

    init(payload: KeysignPayload) {
        self.payload = payload
    }

    func getKeysignMessages(vault: Vault) throws -> [String] {
        var messages: [String] = []

        if let approvePayload =  payload.approvePayload {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            messages += try swaps.getPreSignedApproveImageHash(approvePayload: approvePayload, keysignPayload: payload)
        }

        if let swapPayload = payload.swapPayload {
            let incrementNonce = payload.approvePayload != nil
            switch swapPayload {
            case .thorchain(let swapPayload):
                _ = ThorchainService.shared.ensureTHORChainChainID()
                let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
                messages += try swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
            case .oneInch(let swapPayload):
                let swaps = OneInchSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
                messages += try swaps.getPreSignedImageHash(payload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
            case .mayachain:
                break // No op - Regular transaction with memo
            }
        }

        if !messages.isEmpty {
            return messages
        }

        switch payload.coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let utxoHelper = UTXOChainsHelper(coin: payload.coin.chain.coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return try utxoHelper.getPreSignedImageHash(keysignPayload: payload)
        case .ethereum, .arbitrum, .base, .optimism, .polygon, .avalanche, .bscChain, .blast, .cronosChain, .zksync:
            if payload.coin.isNativeToken {
                return try EVMHelper.getHelper(coin: payload.coin).getPreSignedImageHash(keysignPayload: payload)
            } else {
                return try ERC20Helper.getHelper(coin: payload.coin).getPreSignedImageHash(keysignPayload: payload)
            }
        case .thorChain:
            _ = ThorchainService.shared.ensureTHORChainChainID()
            return try THORChainHelper.getPreSignedImageHash(keysignPayload: payload)
        case .mayaChain:
            return try MayaChainHelper.getPreSignedImageHash(keysignPayload: payload)
        case .solana:
            return try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        case .sui:
            return try SuiHelper.getPreSignedImageHash(keysignPayload: payload)
        case .gaiaChain:
            return try ATOMHelper().getPreSignedImageHash(keysignPayload: payload)
        case .kujira:
            return try KujiraHelper().getPreSignedImageHash(keysignPayload: payload)
        case .osmosis:
            return try OsmoHelper().getPreSignedImageHash(keysignPayload: payload)
        case .polkadot:
            return try PolkadotHelper.getPreSignedImageHash(keysignPayload: payload)
        case .dydx:
            return try DydxHelper().getPreSignedImageHash(keysignPayload: payload)
        case .ton:
            return try TonHelper.getPreSignedImageHash(keysignPayload: payload)
        }
    }
}
