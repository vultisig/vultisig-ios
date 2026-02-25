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

    func getKeysignMessages() throws -> [String] {
        var messages: [String] = []

        if let approvePayload =  payload.approvePayload {
            let swaps = THORChainSwaps()
            messages += try swaps.getPreSignedApproveImageHash(approvePayload: approvePayload, keysignPayload: payload)
        }
        if let swapPayload = payload.swapPayload {
            let incrementNonce = payload.approvePayload != nil
            switch swapPayload {
            case .thorchain(let swapPayload):
                let service = ThorchainServiceFactory.getService(for: .thorChain)
                _ = service.ensureTHORChainChainID()
                let swaps = THORChainSwaps()
                messages += try swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
            case .thorchainChainnet(let swapPayload):
                let service = ThorchainServiceFactory.getService(for: .thorChainChainnet)
                _ = service.ensureTHORChainChainID()
                let swaps = THORChainSwaps()
                messages += try swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
            case .thorchainStagenet(let swapPayload):
                let service = ThorchainServiceFactory.getService(for: .thorChainStagenet)
                _ = service.ensureTHORChainChainID()
                let swaps = THORChainSwaps()
                messages += try swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
            case .generic(let swapPayload):
                switch payload.coin.chain {
                case .solana:
                    let swaps = SolanaSwaps()
                    messages = try swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload)
                default:
                    let swaps = OneInchSwaps()
                    messages += try swaps.getPreSignedImageHash(payload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
                }
            case .mayachain(let swapPayload):
                // for MayaChain swaps, when it is a native token , then we just convert it to a normal send transaction
                // Only when it is an ERC20 token we use the swap logic of thorchain
                if payload.coin.chain.chainType != .EVM  || payload.coin.isNativeToken {
                    break
                }
                let swaps = THORChainSwaps()
                messages += try swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload, incrementNonce: incrementNonce)
            }
        }

        if !messages.isEmpty {
            return messages
        }

        switch payload.coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            let utxoHelper = UTXOChainsHelper(coin: payload.coin.chain.coinType)
            return try utxoHelper.getPreSignedImageHash(keysignPayload: payload)
        case .cardano:
            return try CardanoHelper.getPreSignedImageHash(keysignPayload: payload)
        case .ethereum, .arbitrum, .base, .optimism, .polygon, .polygonV2, .avalanche, .bscChain, .blast, .cronosChain, .zksync, .ethereumSepolia, .mantle, .hyperliquid, .sei:
            if payload.coin.isNativeToken {
                return try EVMHelper.getHelper(coin: payload.coin).getPreSignedImageHash(keysignPayload: payload)
            } else {
                return try ERC20Helper.getHelper(coin: payload.coin).getPreSignedImageHash(keysignPayload: payload)
            }
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            let service = ThorchainServiceFactory.getService(for: payload.coin.chain)
            _ = service.ensureTHORChainChainID()
            return try THORChainHelper.getPreSignedImageHash(keysignPayload: payload)
        case .mayaChain:
            return try MayaChainHelper.getPreSignedImageHash(keysignPayload: payload)
        case .solana:
            return try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        case .sui:
            return try SuiHelper.getPreSignedImageHash(keysignPayload: payload)
        case .gaiaChain, .kujira, .osmosis, .terra, .terraClassic, .noble, .dydx, .akash:
            let helper = try CosmosHelper.getHelper(forChain: payload.coin.chain)
            return try helper.getPreSignedImageHash(keysignPayload: payload)
        case .polkadot:
            return try PolkadotHelper.getPreSignedImageHash(keysignPayload: payload)
        case .ton:
            return try TonHelper.getPreSignedImageHash(keysignPayload: payload)
        case .ripple:
            return try RippleHelper.getPreSignedImageHash(keysignPayload: payload)
        case .tron:
            return try TronHelper.getPreSignedImageHash(keysignPayload: payload)
        }
    }
}
