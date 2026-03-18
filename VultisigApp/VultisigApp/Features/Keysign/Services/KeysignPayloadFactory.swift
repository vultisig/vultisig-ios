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
        case .UTXO, .Cardano:
            // Use WalletCore transaction planning for UTXO selection (both UTXO and Cardano chains)
            let payload = KeysignPayload(
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
                tronTransferContractPayload: nil,
                tronTriggerSmartContractPayload: nil,
                tronTransferAssetContractPayload: nil,
                skipBroadcast: false,
                signData: nil
            )

            // Select appropriate UTXO selection method based on chain
            if coin.chain == .cardano {
                utxos = try await selectCardanoUTXOs(keysignPayload: payload)
            } else {
                utxos = try await selectUTXOs(keysignPayload: payload)
            }

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
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func selectUTXOs(keysignPayload: KeysignPayload) async throws -> [UtxoInfo] {
        let info = await utxo.getByKey(key: keysignPayload.coin.blockchairKey)?.utxo?.map({
            UtxoInfo(
                hash: $0.transactionHash ?? "",
                amount: Int64($0.value ?? 0),
                index: UInt32($0.index ?? -1)
            )
        })
        guard let utxosInfo = info else {
            return []
        }

        let dustThreshold = keysignPayload.coin.coinType.getFixedDustThreshold()
        let usableUTXOs = utxosInfo.filter { $0.amount >= dustThreshold }
        if usableUTXOs.isEmpty {
            throw Errors.utxoTooSmallError
        }
        let helper = UTXOChainsHelper.getHelper(coin: keysignPayload.coin)
        guard let utxoHelper = helper else {
            throw Errors.utxoSelectionFailedError
        }
        let tmpKeysignPayload = KeysignPayload(
            coin: keysignPayload.coin,
            toAddress: keysignPayload.toAddress,
            toAmount: keysignPayload.toAmount,
            chainSpecific: keysignPayload.chainSpecific,
            utxos: usableUTXOs,
            memo: keysignPayload.memo,
            swapPayload: keysignPayload.swapPayload,
            approvePayload: keysignPayload.approvePayload,
            vaultPubKeyECDSA: keysignPayload.vaultPubKeyECDSA,
            vaultLocalPartyID: keysignPayload.vaultLocalPartyID,
            libType: keysignPayload.libType,
            wasmExecuteContractPayload: keysignPayload.wasmExecuteContractPayload,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: keysignPayload.skipBroadcast,
            signData: nil
        )

        let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: tmpKeysignPayload)
        if plan.utxos.isEmpty {
            throw Errors.notEnoughUTXOError
        }
        return plan.utxos.map { utxo in
            UtxoInfo(
                hash: utxo.outPoint.hash.reversed().toHexString(),
                amount: utxo.amount,
                index: utxo.outPoint.index
            )
        }
    }

    private func selectCardanoUTXOs(keysignPayload: KeysignPayload) async throws -> [UtxoInfo] {
        // Fetch all available UTXOs for Cardano using Koios API
        let cardanoUTXOs = try await CardanoService.shared.getUTXOs(coin: keysignPayload.coin)

        guard !cardanoUTXOs.isEmpty else {
            throw Errors.notEnoughUTXOError
        }

        // Create temporary payload with all available UTXOs for WalletCore planning
        let tmpKeysignPayload = KeysignPayload(
            coin: keysignPayload.coin,
            toAddress: keysignPayload.toAddress,
            toAmount: keysignPayload.toAmount,
            chainSpecific: keysignPayload.chainSpecific,
            utxos: cardanoUTXOs,
            memo: keysignPayload.memo,
            swapPayload: keysignPayload.swapPayload,
            approvePayload: keysignPayload.approvePayload,
            vaultPubKeyECDSA: keysignPayload.vaultPubKeyECDSA,
            vaultLocalPartyID: keysignPayload.vaultLocalPartyID,
            libType: keysignPayload.libType,
            wasmExecuteContractPayload: keysignPayload.wasmExecuteContractPayload,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: keysignPayload.skipBroadcast,
            signData: nil
        )

        // Use WalletCore's Cardano transaction planning to select optimal UTXOs
        let cardanoHelper = CardanoHelper()

        let plan = try cardanoHelper.getCardanoTransactionPlan(keysignPayload: tmpKeysignPayload)
        if plan.utxos.isEmpty {
            throw Errors.notEnoughUTXOError
        }

        // Convert WalletCore's selected UTXOs back to UtxoInfo format
        return plan.utxos.map { utxo in
            UtxoInfo(
                hash: utxo.outPoint.txHash.toHexString(),
                amount: Int64(utxo.amount),
                index: UInt32(utxo.outPoint.outputIndex)
            )
        }
    }
}
