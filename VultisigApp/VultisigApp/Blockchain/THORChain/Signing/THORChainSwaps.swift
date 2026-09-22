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

    /// Effective per-affiliate bps after applying the VULT tier discount,
    /// clamped at zero. Quote request builders use this for the wire
    /// `affiliate_bps`; display surfaces separately show the gross list rate.
    static func discountedAffiliateBps(baseBps: Int, discountBps: Int) -> Int {
        max(0, baseBps - discountBps)
    }

    /// Total affiliate bps the protocol charges for a swap — the sum of every
    /// affiliate entry the request sends. `isReferred` mirrors the request builder's
    /// `!referredCode.isEmpty` branch: a referred swap splits the fee into the
    /// referrer's fixed share plus the discounted Vultisig share. This helper is
    /// wire-focused; the UI itemizes gross fee and discounts separately.
    static func effectiveAffiliateFeeBps(discountBps: Int, isReferred: Bool) -> Int {
        if isReferred {
            let referrerBps = Int(referredUserFeeRateBp) ?? 0
            return referrerBps + discountedAffiliateBps(baseBps: referredAffiliateFeeRateBp, discountBps: discountBps)
        }
        return discountedAffiliateBps(baseBps: affiliateFeeRateBp, discountBps: discountBps)
    }

    init() {}

    func getPreSignedInputData(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, nonceOffset: Int64) throws -> Data {
        switch swapPayload.fromCoin.chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return try THORChainHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let helper = UTXOChainsHelper(coin: swapPayload.fromCoin.coinType)
            let swapInput =  try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload)
            return try helper.getSigningInputData(keysignPayload: keysignPayload, signingInput: swapInput)
        case .ethereum, .bscChain, .avalanche, .base, .arbitrum:
            let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
            let signedEvmTx = try helper.getSwapPreSignedInputData(keysignPayload: keysignPayload, nonceOffset: nonceOffset)
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

    func getPreSignedImageHash(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, nonceOffset: Int64) throws -> [String] {
        let inputData = try getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload, nonceOffset: nonceOffset)

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

    /// One signing input per approve leg, in nonce order: `approve(spender, 0)`
    /// at the payload nonce when the payload asks for an allowance reset, then
    /// `approve(spender, amount)` one nonce later; a single input at the payload
    /// nonce otherwise. Every leg uses the payload's fee fields.
    func getPreSignedApproveInputData(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload) throws -> [Data] {
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        return try approvePayload.legAmounts.enumerated().map { leg, amount in
            let approveInput = EthereumSigningInput.with {
                $0.transaction = .with {
                    $0.erc20Approve = .with {
                        $0.amount = amount.magnitude.serialize()
                        $0.spender = approvePayload.spender
                    }
                }
                $0.toAddress = keysignPayload.coin.contractAddress
            }
            return try helper.getPreSignedInputData(
                signingInput: approveInput,
                keysignPayload: keysignPayload,
                nonceOffset: Int64(leg)
            )
        }
    }

    func getPreSignedApproveImageHash(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        return try inputData.map {
            let hashes = TransactionCompiler.preImageHashes(coinType: keysignPayload.coin.coinType, txInputData: $0)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
            if !preSigningOutput.errorMessage.isEmpty {
                throw HelperError.runtimeError(preSigningOutput.errorMessage)
            }
            return preSigningOutput.dataHash.hexString
        }
    }

    /// The signed approve legs, in the nonce order they were built.
    func getSignedApproveTransactions(approvePayload: ERC20ApprovePayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse]) throws -> [SignedTransactionResult] {
        let inputData = try getPreSignedApproveInputData(
            approvePayload: approvePayload,
            keysignPayload: keysignPayload
        )
        let helper = EVMHelper.getHelper(coin: keysignPayload.coin)
        return try inputData.map {
            try helper.getSignedTransaction(ethPublicKey: keysignPayload.coin.hexPublicKey, inputData: $0, signatures: signatures)
        }
    }

    func getSignedTransaction(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload, signatures: [String: TssKeysignResponse], nonceOffset: Int64) throws -> SignedTransactionResult {

        let inputData = try getPreSignedInputData(
            swapPayload: swapPayload,
            keysignPayload: keysignPayload,
            nonceOffset: nonceOffset
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
