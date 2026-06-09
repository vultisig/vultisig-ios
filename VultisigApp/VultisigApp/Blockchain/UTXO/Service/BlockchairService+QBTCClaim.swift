//
//  BlockchairService+QBTCClaim.swift
//  VultisigApp
//
//  Discovery of unspent Bitcoin UTXOs that may be claimed on QBTC.
//  Mirrors vultisig-sdk/.../getClaimableUtxos.ts: lookup-only, no
//  filtering of already-claimed UTXOs. The chain rejects them at
//  execution; tracked at btcq-org/qbtc#134.
//

import Foundation

/// The unspent Bitcoin UTXOs at an address plus the chain tip height that
/// the same Blockchair response reported. The tip is needed to compute each
/// UTXO's confirmation count for the QBTC claim confirmation gate; it is
/// `nil` when Blockchair omits `context.state` (the gate then fails open —
/// see `QBTCChainService.filterSufficientlyConfirmed`).
struct QBTCClaimableUtxosResult {
    let utxos: [ClaimableUtxo]
    let btcTipHeight: UInt32?
}

enum QBTCClaimableUtxosError: Error {
    /// Blockchair returned a response that lacks the requested address key.
    /// Treated as a fetch/normalization failure (propagated) rather than an
    /// empty UTXO set, so a backend hiccup can't masquerade as "nothing to
    /// claim".
    case missingAddressData(String)
}

extension BlockchairService {
    /// Fetches the unspent Bitcoin UTXOs at `address`, adapts them to
    /// `ClaimableUtxo`, and surfaces the chain tip height from the same
    /// Blockchair response. Reuses the existing blockchair fetch (and cache).
    ///
    /// The tip comes from `context.state` (the latest block Blockchair has
    /// indexed) so confirmations can be computed without an extra round-trip.
    ///
    /// - Parameters:
    ///   - bitcoinCoin: The Bitcoin coin meta (caller supplies this from
    ///     the active vault). Must be a Bitcoin coin — `bitcoinCoin.chain`
    ///     is used to build the blockchair endpoint.
    ///   - address: The Bitcoin address that controls the UTXOs.
    func fetchQBTCClaimableUtxos(
        bitcoinCoin: CoinMeta,
        address: String
    ) async throws -> QBTCClaimableUtxosResult {
        let response = try await fetchBlockchairResponse(coin: bitcoinCoin, address: address)
        // A missing address key means the fetch/normalization failed, not that
        // the address has zero UTXOs — surface it as an error so the claim flow
        // can fail-closed instead of telling the user there's nothing to claim.
        guard let blockchair = response.data[address] else {
            throw QBTCClaimableUtxosError.missingAddressData(address)
        }
        let utxos = (blockchair.utxo ?? []).compactMap(ClaimableUtxo.init(blockchair:))
        let tip = response.context?.state.flatMap { $0 > 0 ? UInt32(exactly: $0) : nil }
        return QBTCClaimableUtxosResult(utxos: utxos, btcTipHeight: tip)
    }
}

extension ClaimableUtxo {
    /// Maps a Blockchair UTXO row to a `ClaimableUtxo`. Returns `nil`
    /// when any required field is missing or invalid (negative values,
    /// missing txid, etc.) — mirrors the SDK behaviour of dropping
    /// malformed entries rather than failing the whole request.
    init?(blockchair: Blockchair.BlockchairUtxo) {
        guard let txid = blockchair.transactionHash,
              !txid.isEmpty,
              let index = blockchair.index,
              let vout = UInt32(exactly: index),
              let value = blockchair.value,
              let amount = UInt64(exactly: value) else {
            return nil
        }
        let blockHeight = blockchair.blockId.flatMap { $0 > 0 ? UInt32(exactly: $0) : nil }
        self.init(txid: txid, vout: vout, amount: amount, blockHeight: blockHeight)
    }
}
