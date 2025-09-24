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
        case notEnoughUTXOError
        case utxoTooSmallError
        case utxoSelectionFailedError
        case failToGetAccountNumber
        case failToGetSequenceNo
        case failToGetRecentBlockHash
        
        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }
    
    private let utxo = BlockchairService.shared
    private let thor = ThorchainService.shared
    private let sol = SolanaService.shared
    
    func buildTransfer(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        chainSpecific: BlockChainSpecific,
        swapPayload: SwapPayload? = nil,
        approvePayload: ERC20ApprovePayload? = nil,
        vault: Vault,
        wasmExecuteContractPayload: WasmExecuteContractPayload? = nil
    ) async throws -> KeysignPayload {
        
        var utxos: [UtxoInfo] = []
        
        switch chainSpecific {
        case .Cardano(let byteFee, let sendMaxAmount, _):
            // Fetch UTXOs for Cardano using Koios API
            do {
                let cardanoUTXOs = try await CardanoService.shared.getUTXOs(coin: coin)
                
                // For send max, don't add fees - let WalletCore handle it
                // For regular sends, add estimated fees to ensure we have enough
                let totalNeeded: BigInt
                if sendMaxAmount {
                    totalNeeded = amount // Don't add fees for send max
                } else {
                    totalNeeded = amount + BigInt(byteFee) // Add fees for regular sends
                }
                
                var selectedUTXOs: [UtxoInfo] = []
                var totalSelected: Int64 = 0
                
                // Sort UTXOs by amount (smallest first for better UTXO management)
                let sortedUTXOs = cardanoUTXOs.sorted { $0.amount < $1.amount }
                
                for utxo in sortedUTXOs {
                    selectedUTXOs.append(utxo)
                    totalSelected += utxo.amount
                    
                    if totalSelected >= Int64(totalNeeded) {
                        break
                    }
                }
                
                guard !selectedUTXOs.isEmpty && (sendMaxAmount || totalSelected >= Int64(totalNeeded)) else {
                    throw Errors.notEnoughBalanceError
                }
                
                utxos = selectedUTXOs
            } catch {
                throw Errors.notEnoughBalanceError
            }
            
        case .UTXO(let byteFee, _):
            // Bitcoin, Litecoin, Dogecoin etc. - use Blockchair
            // 148 is estimate vbytes for every input
            // estimate we will use maximum 10 utxos
            let totalAmount = amount + BigInt(byteFee * 1480)
            guard let info = utxo.blockchairData
                .get(coin.blockchairKey)?.selectUTXOsForPayment(amountNeeded: Int64(totalAmount),coinType: coin.coinType)
                .map({
                    UtxoInfo(
                        hash: $0.transactionHash ?? "",
                        amount: Int64($0.value ?? 0),
                        index: UInt32($0.index ?? -1)
                    )
                }), !info.isEmpty else {
                // Check what specific UTXO issue we have
                if let blockchairData = utxo.blockchairData.get(coin.blockchairKey) {
                    if blockchairData.utxo?.isEmpty ?? true {
                        throw Errors.notEnoughUTXOError
                    }
                    let dustThreshold = coin.coinType.getFixedDustThreshold()
                    let usableUtxos = blockchairData.utxo?.filter { ($0.value ?? 0) >= Int(dustThreshold) } ?? []
                    if usableUtxos.isEmpty {
                        throw Errors.utxoTooSmallError
                    }
                    throw Errors.utxoSelectionFailedError
                }
                throw Errors.notEnoughBalanceError
            }
            utxos = info
            
        default:
            // Non-UTXO chains don't need UTXO selection
            break
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
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20).toString(),
            wasmExecuteContractPayload: wasmExecuteContractPayload,
            skipBroadcast: false
        )
    }
}
