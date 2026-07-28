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
        // Mutable so Cardano can replace the placeholder `byteFee` with the real
        // size-based fee once UTXOs are selected (see below).
        var resolvedChainSpecific = chainSpecific

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
                qbtcClaimPayload: nil,
                isQbtcClaim: false,
                skipBroadcast: false,
                signData: nil
            )

            // Select appropriate UTXO selection method based on chain
            if coin.chain == .cardano {
                utxos = try await selectCardanoUTXOs(keysignPayload: payload)
                // As the initiator, compute the real size-based fee ONCE over the
                // selected UTXOs/outputs and bake it into `byteFee`. This fee is a
                // shared payload constant that every co-signing device forces
                // identically, guaranteeing byte-identical Cardano body bytes (and
                // thus Blake2b sighash parity) across iOS/SDK/Windows/Android. The
                // upstream `fetchSpecific` seeds `byteFee` with a flat placeholder
                // because UTXOs aren't selected yet; we replace it here.
                if case .Cardano(_, let sendMaxAmount, let ttl) = chainSpecific {
                    let feedPayload = makeCardanoFeePayload(
                        coin: coin,
                        toAddress: toAddress,
                        amount: amount,
                        memo: memo,
                        ttl: ttl,
                        sendMaxAmount: sendMaxAmount,
                        utxos: utxos,
                        vault: vault
                    )
                    let dynamicFee = CardanoHelper.estimateDynamicByteFee(keysignPayload: feedPayload)
                    resolvedChainSpecific = .Cardano(byteFee: dynamicFee, sendMaxAmount: sendMaxAmount, ttl: ttl)
                }
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
            chainSpecific: resolvedChainSpecific,
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
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    /// Build a transient payload carrying the selected Cardano UTXOs, used only
    /// to run the initiator's preliminary fee plan (`estimateDynamicByteFee`).
    /// `byteFee` is left at 0 so the planner derives a size-based fee. The memo
    /// must be carried through: a CIP-20 memo grows the signed tx (aux-hash
    /// entry in the body plus the aux CBOR in the envelope), and a fee planned
    /// without it is below the network minimum for the tx that actually gets
    /// signed — the node rejects the broadcast with `FeeTooSmallUTxO`.
    /// Internal (not private) so the fee tests can pin this behavior.
    func makeCardanoFeePayload(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        ttl: UInt64,
        sendMaxAmount: Bool,
        utxos: [UtxoInfo],
        vault: Vault
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount,
            chainSpecific: .Cardano(byteFee: 0, sendMaxAmount: sendMaxAmount, ttl: ttl),
            utxos: utxos,
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20).toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func selectUTXOs(keysignPayload: KeysignPayload) async throws -> [UtxoInfo] {
        let dustThreshold = keysignPayload.coin.coinType.getFixedDustThreshold()
        let usableUTXOs: [UtxoInfo]

        if keysignPayload.coin.chain == .dash {
            // Dash reads its UTXOs from a node's address index via
            // `getaddressutxos`, which is built from connected blocks —
            // mempool outputs live behind a separate RPC and never appear
            // here. Every entry is confirmed by construction, so the
            // confirmation filter the Blockchair path applies would be dead
            // code; the SDK's Dash client filters on dust alone for the same
            // reason.
            let dashUTXOs = try await DashService.shared.fetchUtxos(
                address: keysignPayload.coin.address
            )
            usableUTXOs = dashUTXOs.filter { $0.amount >= dustThreshold }
        } else {
            // Blockchair path for every other UTXO chain.
            guard let rows = await utxo.getByKey(key: keysignPayload.coin.blockchairKey)?.utxo else {
                throw Errors.notEnoughUTXOError
            }
            usableUTXOs = Self.spendableUTXOs(from: rows, dustThreshold: dustThreshold)
        }

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
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
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
        // Mirror SDK behaviour: ship every available UTXO at the address as
        // an input. WalletCore's Cardano signer picks what it needs at
        // build time. We deliberately don't run `AnySigner.plan(...)` here
        // because its UTXO selection trips `errorLowBalance` on CNT sends —
        // see `Cardano.swift:getCardanoPreSignInputData` for the rationale.
        //
        // The initiator (this code) is the only side that hits Koios; per-UTxO
        // token data crosses the wire via `UtxoInfo.cardanoTokens`. Cosigners
        // read those bytes verbatim — no extra Koios call, no fetch-ordering
        // drift, identical input bytes on both peers by construction.
        let extendedUTXOs = try await CardanoService.shared.getExtendedUTXOs(coin: keysignPayload.coin)

        guard !extendedUTXOs.isEmpty else {
            throw Errors.notEnoughUTXOError
        }

        return extendedUTXOs.map { utxo in
            // Sort tokens canonically so the proto serialises identically
            // regardless of Koios's per-response ordering — keeps the keysign
            // session id stable across retries.
            let sortedAssets = utxo.assets.sorted { lhs, rhs in
                if lhs.policyId != rhs.policyId { return lhs.policyId < rhs.policyId }
                return lhs.assetNameHex < rhs.assetNameHex
            }
            return UtxoInfo(
                hash: utxo.hash,
                amount: Int64(utxo.amount),
                index: utxo.index,
                cardanoTokens: sortedAssets
            )
        }
    }
}

extension KeysignPayloadFactory {

    /// Narrows Blockchair's rows to the outputs that may fund a transaction,
    /// adopting the SDK's `is_spendable !== false && block_id > 0` alongside
    /// the dust threshold this path already applied. The dust comparison stays
    /// inclusive (`>= dustThreshold`) rather than the SDK's strict `>`: that
    /// boundary predates this filter and moving it would drop outputs iOS can
    /// spend today.
    ///
    /// The confirmation half of that predicate is the load-bearing one here:
    /// Blockchair's `utxo` array includes mempool outputs (`block_id == -1`),
    /// and an unconfirmed parent can still be replaced or evicted — leaving a
    /// child that can never confirm. The response carries no ancestry, so
    /// there is no way to tell our own change from an inbound zero-conf
    /// payment the sender can still double-spend, and the MPC pairing window
    /// leaves minutes for either to happen between selection and broadcast.
    ///
    /// Rows missing the fields needed to build an input are dropped rather
    /// than failing the whole set, matching the previous behaviour.
    static func spendableUTXOs(
        from rows: [Blockchair.BlockchairUtxo],
        dustThreshold: Int64
    ) -> [UtxoInfo] {
        rows.compactMap { row -> UtxoInfo? in
            guard row.isSpendableCandidate,
                  let txHash = row.transactionHash, !txHash.isEmpty,
                  let value = row.value, let amount = Int64(exactly: value), amount >= dustThreshold,
                  let index = row.index, let vout = UInt32(exactly: index)
            else {
                return nil
            }
            return UtxoInfo(hash: txHash, amount: amount, index: vout)
        }
    }
}
