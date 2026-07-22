//
//  THORChainSwaps.swift
//  VultisigApp
//

import Foundation
import Tss
import WalletCore

class THORChainSwaps {
    static var affiliateFeeRateBp: Int {
#if DEBUG
        return 0
#else
        return 50
#endif
    }

    static var referredAffiliateFeeRateBp: Int {
        return 35
    }

    static var referredUserFeeRateBp: String {
        return "10"
    }

    static let affiliateFeeAddress = "vi"

    /// SwapKit's affiliate share is set on the partner dashboard, not sent per
    /// transaction, so it's a fixed 0.50% baked into the quoted rate regardless
    /// of build (the DEBUG toggle on `affiliateFeeRateBp` only affects the
    /// native `affiliate_bps` we send ourselves).
    static let swapKitAffiliateFeeBps = 50

    /// Effective per-affiliate bps after applying the VULT tier discount,
    /// clamped at zero. Single source of truth consumed by BOTH the quote
    /// request builders (the `affiliate_bps` query param) and the fee-percentage
    /// display, so the shown % equals the bps actually sent by construction.
    static func discountedAffiliateBps(baseBps: Int, discountBps: Int) -> Int {
        max(0, baseBps - discountBps)
    }

    /// Total affiliate bps the protocol charges for a swap — the sum of every
    /// affiliate entry the request sends. The node computes `fees.affiliate`
    /// from this, so it is the number behind the "Vultisig Fee (X.XX%)"
    /// percentage and reconciles with the shown affiliate amount by
    /// construction. `isReferred` mirrors the request builder's
    /// `!referredCode.isEmpty` branch: a referred swap splits the fee into the
    /// referrer's fixed share plus the discounted Vultisig share.
    static func effectiveAffiliateFeeBps(discountBps: Int, isReferred: Bool) -> Int {
        if isReferred {
            let referrerBps = Int(referredUserFeeRateBp) ?? 0
            return referrerBps + discountedAffiliateBps(baseBps: referredAffiliateFeeRateBp, discountBps: discountBps)
        }
        return discountedAffiliateBps(baseBps: affiliateFeeRateBp, discountBps: discountBps)
    }

    init() {}

    func getPreSignedInputData(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> Data {
        switch swapPayload.fromCoin.chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return try THORChainHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let helper = UTXOChainsHelper(coin: swapPayload.fromCoin.coinType)
            let swapInput =  try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
            return try helper.getSigningInputData(keysignPayload: keysignPayload, signingInput: swapInput)
        case .ethereum, .bscChain, .avalanche, .base, .arbitrum:
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
            let signedEvmTx = try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload, incrementNonce: incrementNonce)
            return signedEvmTx
        case .gaiaChain:
            let helper = try CosmosHelper.getHelper(forChain: .gaiaChain)
            return try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .ripple:
            return try RippleHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .tron:
            return try TronHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .solana:
            return try SolanaHelper.getPreSignedInputData(keysignPayload: keysignPayload)
        default:
            throw HelperError.runtimeError("not support yet")
        }
    }

    func getPreSignedImageHash(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, incrementNonce: Bool) throws -> [String] {
        let inputData = try getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload, incrementNonce: incrementNonce)

        switch swapPayload.fromCoin.chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet, .ethereum, .bscChain, .avalanche, .gaiaChain, .base, .arbitrum:
            let hashes = TransactionCompiler.preImageHashes(coinType: swapPayload.fromCoin.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            if !preSigningOutput.errorMessage.isEmpty {
                throw HelperError.runtimeError(preSigningOutput.errorMessage)
            }
            return [preSigningOutput.dataHash.hexString]
        case .bitcoin, .litecoin, .bitcoinCash, .dogecoin:
            let hashes = TransactionCompiler.preImageHashes(coinType: swapPayload.fromCoin.coinType, txInputData: inputData)
            let preSigningOutput = try BitcoinPreSigningOutput(serializedBytes: hashes)
            if !preSigningOutput.errorMessage.isEmpty {
                throw HelperError.runtimeError(preSigningOutput.errorMessage)
            }
            return preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString }
        case .ripple:
            return try RippleHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .tron:
            return try TronHelper.getPreSignedImageHash(keysignPayload: keysignPayload)
        case .solana:
            return try SolanaHelper.getPreSignedImageHash(inputData: inputData)
        default:
            throw HelperError.runtimeError("not support yet")
        }
    }

    func getPreSignedApproveInputData(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload) throws -> Data {
        let approveInput = EthereumSigningInput.with {
            $0.transaction = .with {
                $0.erc20Approve = .with {
                    $0.amount = approvePayload.amount.magnitude.serialize()
                    $0.spender = approvePayload.spender
                }
            }
            $0.toAddress = keysignPayload.coin.contractAddress
        }
        let inputData = try EVMHelper.getHelper(coin: keysignPayload.coin).getPreSignedInputData(
            signingInput: approveInput,
            keysignPayload: keysignPayload
        )
        return inputData
    }

    func getPreSignedApproveImageHash(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        let hashes = TransactionCompiler.preImageHashes(coinType: keysignPayload.coin.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        return [preSigningOutput.dataHash.hexString]
    }

    func getSignedApproveTransaction(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        let signedEvmTx = try EVMHelper.getHelper(coin: keysignPayload.coin).getSignedTransaction(ethPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        return signedEvmTx
    }

    func getSignedTransaction(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], incrementNonce: Bool) throws -> SignedTransactionResult {

        let inputData = try getPreSignedInputData(
            swapPayload: swapPayload,
            keysignPayload: keysignPayload,
            incrementNonce: incrementNonce
        )

        switch swapPayload.fromCoin.chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return try THORChainHelper.getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        case .bitcoin:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoin)
            return try utxoHelper.getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        case .bitcoinCash:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash)
            return try utxoHelper.getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        case .litecoin:
            let utxoHelper = UTXOChainsHelper(coin: .litecoin)
            return try utxoHelper.getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        case .dogecoin:
            let utxoHelper = UTXOChainsHelper(coin: .dogecoin)
            return try utxoHelper.getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        case .ethereum, .bscChain, .avalanche, .base, .arbitrum:
            let signedEvmTx = try EVMHelper.getHelper(coin: keysignPayload.coin).getSignedTransaction(ethPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
            return signedEvmTx
        case .gaiaChain:
            let helper = try CosmosHelper.getHelper(forChain: .gaiaChain)
            return try helper.getSignedTransaction(coinHexPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        case .ripple:
            return try RippleHelper.getSignedTransaction(keysignPayload: keysignPayload, signatures: signatures)
        case .tron:
            return try TronHelper.getSignedTransaction(
                keysignPayload: keysignPayload,
                signatures: signatures)
        case .solana:
            return try SolanaHelper.getSignedTransaction(coinHexPubKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        default:
            throw HelperError.runtimeError("not support")
        }
    }
}
