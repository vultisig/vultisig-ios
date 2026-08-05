//
//  KaminoKeysignPayloadFactory.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Assembles the `KeysignPayload` for a prepared Kamino transaction.
///
/// The signed artefact is `signData` and nothing else: `SolanaHelper` signs those
/// wire bytes verbatim, and every account and amount in them has already been
/// checked against the registry by `KaminoTransactionValidator`. The rest of the
/// payload is context — what the verify screen shows, what the fee display reads,
/// which key signs — so it is filled in to describe the same transaction rather
/// than to define it.
enum KaminoKeysignPayloadFactory {

    enum Errors: Error, LocalizedError, Equatable {
        /// The compute limit is a `u32` on chain and a `BigInt` in
        /// `BlockChainSpecific`; a value that cannot make the round trip would
        /// misreport the fee.
        case priorityLimitOutOfRange(UInt32)

        var errorDescription: String? {
            switch self {
            case .priorityLimitOutOfRange(let limit):
                return "Compute unit limit \(limit) cannot be represented"
            }
        }
    }

    /// - Parameters:
    ///   - coin: the coin being deposited. On Solana every coin of the vault
    ///     shares one address and one public key, so this decides what the user
    ///     is shown, not who signs.
    static func makeDeposit(
        prepared: KaminoPreparedTransaction,
        vaultInfo: KaminoVaultInfo,
        amount: KaminoTokenAmount,
        coin: Coin,
        vault: Vault
    ) throws -> KeysignPayload {
        try make(
            prepared: prepared,
            vault: vault,
            coin: coin,
            // A deposit leaves the wallet for the vault, and its amount is in the
            // underlying token — the same unit the bytes carry.
            toAddress: vaultInfo.descriptor.address,
            toAmount: amount.baseUnits,
            marker: KaminoKeysignPayload(
                vaultAddress: vaultInfo.descriptor.address,
                operation: .deposit,
                amount: amount
            )
        )
    }

    /// - Parameters:
    ///   - shares: the SHARE amount the withdraw instruction carries. This is
    ///     what the validator pinned and what the marker records — the bytes are
    ///     denominated in shares, not in the asset.
    ///   - tokenValue: the same withdraw expressed in the underlying asset, for
    ///     the summary the user reads. A projection at the current rate, so it
    ///     never sizes anything.
    static func makeWithdraw(
        prepared: KaminoPreparedTransaction,
        vaultInfo: KaminoVaultInfo,
        shares: KaminoShareAmount,
        tokenValue: KaminoTokenAmount,
        coin: Coin,
        vault: Vault
    ) throws -> KeysignPayload {
        try make(
            prepared: prepared,
            vault: vault,
            coin: coin,
            // A withdraw pays the user's own account, so that is the destination
            // — not the vault, which is where the funds come from.
            toAddress: coin.address,
            toAmount: tokenValue.baseUnits,
            marker: KaminoKeysignPayload(
                vaultAddress: vaultInfo.descriptor.address,
                operation: .withdraw,
                amount: shares
            )
        )
    }

    private static func make(
        prepared: KaminoPreparedTransaction,
        vault: Vault,
        coin: Coin,
        toAddress: String,
        toAmount: BigInt,
        marker: KaminoKeysignPayload
    ) throws -> KeysignPayload {
        guard let priorityLimit = BigInt(exactly: prepared.priorityFee.limit) else {
            throw Errors.priorityLimitOutOfRange(prepared.priorityFee.limit)
        }

        // Mirrors what is actually inside the bytes: the blockhash they carry,
        // and the compute budget this app injected. Nothing here re-derives the
        // transaction — the Solana signing path takes `signData` when it is
        // present — but the fee display reads these, so they must not describe a
        // different transaction from the one being signed.
        let chainSpecific = BlockChainSpecific.Solana(
            recentBlockHash: prepared.recentBlockhash,
            priorityFee: BigInt(prepared.priorityFee.price),
            priorityLimit: priorityLimit,
            fromAddressPubKey: nil,
            toAddressPubKey: nil,
            hasProgramId: false
        )

        return KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
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
            kaminoPayload: marker,
            skipBroadcast: false,
            signData: .signSolana(SignSolana(rawTransactions: [prepared.base64]))
        )
    }
}
