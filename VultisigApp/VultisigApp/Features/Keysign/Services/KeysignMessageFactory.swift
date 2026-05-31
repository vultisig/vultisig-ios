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
                    messages = try SolanaHelper.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: payload)
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
            case .swapkit(let swapKitPayload):
                // Dispatch on SwapKit's `meta.txType`. For chains where the
                // SwapKit wire shape is a plain native send (TON transfer,
                // ADA deposit), we fall through to the per-chain helper at
                // the bottom of this method — `keysignPayload.toAddress` /
                // `toAmount` have already been set to SwapKit's deposit
                // address + amount by `SwapPayloadBuilder`. PSBT (BTC), SUI
                // (pre-built PTB), and TRON (pre-built raw_data_hex) need
                // SwapKit-specific signers since their pre-built bytes drive
                // the signing input directly.
                switch swapKitPayload.txType {
                case "PSBT":
                    messages += try SwapKitBTCSigner.preSigningHashes(payload: swapKitPayload)
                case "PSBT_DOGE":
                    messages += try SwapKitDogeSigner.preSigningHashes(payload: swapKitPayload)
                case "PSBT_BCH":
                    messages += try SwapKitBCHSigner.preSigningHashes(payload: swapKitPayload)
                case "PSBT_DASH":
                    messages += try SwapKitDashSigner.preSigningHashes(payload: swapKitPayload)
                case "PSBT_ZEC":
                    messages += try SwapKitZcashSigner.preSigningHashes(payload: swapKitPayload)
                case "SUI":
                    messages += try SwapKitSuiSigner.preSigningHashes(payload: swapKitPayload)
                case "TRON":
                    messages += try SwapKitTronSigner.preSigningHashes(payload: swapKitPayload)
                case "CARDANO_PREBUILT":
                    // SwapKit-built CBOR. Hash item 0 of the envelope with
                    // Blake2b-256 — that's the Cardano signing digest.
                    messages += try SwapKitCardanoSigner.preSigningHashes(payload: swapKitPayload)
                case "TON", "CARDANO", "XRP":
                    // Fall through to the existing per-chain helper below
                    // (deposit-only flows: the SwapKit builder already
                    // pointed `toAddress` / `toAmount` at the deposit).
                    // XRP: builder also stringified the destination tag
                    // into `keysignPayload.memo` — `RippleHelper` parses
                    // numeric memos and attaches `destinationTag` on the
                    // `RippleOperationPayment` automatically.
                    break
                case "EVM", "SOLANA":
                    // EVM and Solana ride `SwapPayload.generic` — reaching
                    // this branch means a routing bug.
                    throw SwapKitError.unsupportedTxType(swapKitPayload.txType)
                default:
                    throw SwapKitError.unsupportedTxType(swapKitPayload.txType)
                }
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
        case .gaiaChain, .kujira, .osmosis, .terra, .terraClassic, .noble, .dydx, .akash, .qbtc:
            let helper = try CosmosHelper.getHelper(forChain: payload.coin.chain)
            return try helper.getPreSignedImageHash(keysignPayload: payload)
        case .polkadot:
            return try PolkadotHelper.getPreSignedImageHash(keysignPayload: payload)
        case .bittensor:
            return try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)
        case .ton:
            return try TonHelper.getPreSignedImageHash(keysignPayload: payload)
        case .ripple:
            return try RippleHelper.getPreSignedImageHash(keysignPayload: payload)
        case .tron:
            return try TronHelper.getPreSignedImageHash(keysignPayload: payload)
        }
    }
}
