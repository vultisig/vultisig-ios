//
//  KeysignPayloadFactory.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 09.04.2024.
//

import Foundation
import BigInt

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
        case utxo(amountInSats: Int64, feeInSats: Int64, sendMaxAmount: Bool)
        case evmTransfer(amountInWei: BigInt, gas: String, priorityFeeWei: Int64, nonce: Int64)
        case evmERC20(tokenAmountInWei: BigInt, gas: String, priorityFeeWei: Int64, nonce: Int64)
        case thorchain(amountInSats: Int64, memo: String)
        case gaiachain(amountInCoinDecimal: Int64, memo: String)
        case solana(amountInLamports: Int64, memo: String)
    }

    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let gaia = GaiaService.shared
    private let sol = SolanaService.shared

    func buildTransfer(coin: Coin, toAddress: String, amount: BigInt, memo: String?, chainSpecific: BlockChainSpecific, swapPayload: SwapPayload? = nil, approvePayload: ERC20ApprovePayload? = nil, vault: Vault) async throws -> KeysignPayload {

        var utxos: [UtxoInfo] = []

        if case let .UTXO(byteFee, _) = chainSpecific {
            let totalAmountNeeded = amount + BigInt(byteFee)

            guard let info = utxo.blockchairData.get(coin.blockchairKey)?.selectUTXOsForPayment(amountNeeded: Int64(totalAmountNeeded)).map({
                UtxoInfo(
                    hash: $0.transactionHash ?? "",
                    amount: Int64($0.value ?? 0),
                    index: UInt32($0.index ?? -1)
                )
            }), !info.isEmpty else {
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
            swapPayload: swapPayload,
            approvePayload: approvePayload,
            vaultPubKeyECDSA: vault.pubKeyECDSA, 
            vaultLocalPartyID: vault.localPartyID
        )
    }
}
