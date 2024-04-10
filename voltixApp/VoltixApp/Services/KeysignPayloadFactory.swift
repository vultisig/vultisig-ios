//
//  KeysignPayloadFactory.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 09.04.2024.
//

import Foundation

struct KeysignPayloadFactory {

    enum Errors: String, Error, LocalizedError {
        case notEnoughBalanceError
        case failToGetAccountNumber
        case failToGetSequenceNo
        case failToGetRecentBlockHash

        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }

    enum TransferPayload {
        case utxo(amountInSats: Int64, feeInSats: Int64)
        case evmTransfer(amountInGwei: Int64, gas: String, priorityFeeGwei: Int64, nonce: Int64)
        case evmERC20(tokenAmountInWei: Int64, gas: String, priorityFeeGwei: Int64, nonce: Int64)
        case thorchain(amountInSats: Int64, memo: String)
        case gaiachain(amountInCoinDecimal: Int64, memo: String)
        case solana(amountInLamports: Int64, memo: String)
    }

    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let gaia = GaiaService.shared
    private let sol = SolanaService.shared

    func buildTransfer(coin: Coin, toAddress: String, memo: String, payload: TransferPayload) async throws -> KeysignPayload {
        switch payload {
        case .utxo(let amountInSats, let feeInSats):
            let totalAmountNeeded = amountInSats + feeInSats
            
            guard let utxoInfo = utxo.blockchairData[coin.blockchairKey]?.selectUTXOsForPayment(amountNeeded: totalAmountNeeded).map({
                UtxoInfo(
                    hash: $0.transactionHash ?? "",
                    amount: Int64($0.value ?? 0),
                    index: UInt32($0.index ?? -1)
                )
            }), !utxoInfo.isEmpty else {
                throw Errors.notEnoughBalanceError
            }
            
            let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
            
            if totalSelectedAmount < Int64(totalAmountNeeded) {
                throw Errors.notEnoughBalanceError
            }
            
            return KeysignPayload(
                coin: coin,
                toAddress: toAddress,
                toAmount: amountInSats,
                chainSpecific: BlockChainSpecific.UTXO(byteFee: feeInSats),
                utxos: utxoInfo,
                memo: memo
            )
            
        case .evmTransfer(let amountInGwei, let gas, let priorityFeeGwei, let nonce):
            return KeysignPayload(
                coin: coin,
                toAddress: toAddress,
                toAmount: amountInGwei, // in Gwei
                chainSpecific: BlockChainSpecific.Ethereum(maxFeePerGasGwei: Int64(gas) ?? 24, priorityFeeGwei: priorityFeeGwei, nonce: nonce, gasLimit: EVMHelper.defaultETHTransferGasUnit),
                utxos: [],
                memo: nil
            )
            
        case .evmERC20(let tokenAmountInWei, let gas, let priorityFeeGwei, let nonce):
            return KeysignPayload(
                coin: coin,
                toAddress: toAddress,
                toAmount: tokenAmountInWei, // The amount must be in the token decimals
                chainSpecific: BlockChainSpecific.ERC20(maxFeePerGasGwei: Int64(gas) ?? 42, priorityFeeGwei: priorityFeeGwei, nonce: nonce, gasLimit: EVMHelper.defaultERC20TransferGasUnit, contractAddr: coin.contractAddress),
                utxos: [],
                memo: nil
            )
            
        case .thorchain(let amountInSats, let memo):
            let account = try await thor.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let intAccountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let intSequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            
            return KeysignPayload(
                coin: coin,
                toAddress: toAddress,
                toAmount: amountInSats,
                chainSpecific: BlockChainSpecific.THORChain(accountNumber: intAccountNumber, sequence: intSequence),
                utxos: [],
                memo: memo
            )
            
        case .gaiachain(let amountInCoinDecimal, let memo):
            let account = try await gaia.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let intAccountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let intSequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            
            return KeysignPayload(
                coin: coin,
                toAddress: toAddress,
                toAmount: amountInCoinDecimal,
                chainSpecific: BlockChainSpecific.Cosmos(accountNumber: intAccountNumber, sequence: intSequence, gas: 7500),
                utxos: [],
                memo: memo
            )
            
        case .solana(let amountInLamports, let memo):
            async let recentBlockHashPromise = sol.fetchRecentBlockhash()
            async let highPriorityFeePromise = sol.fetchHighPriorityFee(account: coin.address)
            
            let (recentBlockHash, _) = try await recentBlockHashPromise
            let highPriorityFee = try await highPriorityFeePromise
            
            guard let recentBlockHash else {
                throw Errors.failToGetRecentBlockHash
            }
            
            return KeysignPayload(
                coin: coin,
                toAddress: toAddress,
                toAmount: amountInLamports,
                chainSpecific: BlockChainSpecific.Solana(recentBlockHash: recentBlockHash, priorityFee: highPriorityFee),
                utxos: [],
                memo: memo
            )
        }
    }

    func buildSwap(coin: Coin, swapPayload: THORChainSwapPayload) -> KeysignPayload {
        return KeysignPayload(coin: coin, swapPayload: swapPayload)
    }
}
