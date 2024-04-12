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

    func buildTransfer(coin: Coin, toAddress: String, amount: Int64, memo: String?, chainSpecific: BlockChainSpecific, swapPayload: THORChainSwapPayload? = nil) async throws -> KeysignPayload {

        var utxos: [UtxoInfo] = []

        if case let .UTXO(byteFee) = chainSpecific {
            let totalAmountNeeded = amount + byteFee

            guard let info = utxo.blockchairData[coin.blockchairKey]?.selectUTXOsForPayment(amountNeeded: totalAmountNeeded).map({
                UtxoInfo(
                    hash: $0.transactionHash ?? "",
                    amount: Int64($0.value ?? 0),
                    index: UInt32($0.index ?? -1)
                )
            }), !utxos.isEmpty else {
                throw Errors.notEnoughBalanceError
            }
            utxos = info
        }

        return KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount,
            chainSpecific: chainSpecific,
            utxos: utxos,
            memo: memo,
            swapPayload: swapPayload
        )
    }
}
