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
    
    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let gaia = GaiaService.shared
    private let sol = SolanaService.shared
    
    func buildTransfer(coin: Coin, toAddress: String, amount: BigInt, memo: String?, chainSpecific: BlockChainSpecific, swapPayload: SwapPayload? = nil, approvePayload: ERC20ApprovePayload? = nil, vault: Vault) async throws -> KeysignPayload {
        
        var utxos: [UtxoInfo] = []
        
        if case let .UTXO(byteFee, _) = chainSpecific {
            // 148 is estimate vbytes for every input
            // estimate we will use maximum 10 utxos
            let totalAmount = amount + BigInt(byteFee * 1480)
            guard let info = utxo.blockchairData
                .get(coin.blockchairKey)?.selectUTXOsForPayment(amountNeeded: Int64(totalAmount))
                .map({
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
