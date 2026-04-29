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

extension BlockchairService {
    /// Fetches the unspent Bitcoin UTXOs at `address` and adapts them to
    /// `ClaimableUtxo`. Reuses the existing blockchair fetch (and cache).
    ///
    /// - Parameters:
    ///   - bitcoinCoin: The Bitcoin coin meta (caller supplies this from
    ///     the active vault). Must be a Bitcoin coin — `bitcoinCoin.chain`
    ///     is used to build the blockchair endpoint.
    ///   - address: The Bitcoin address that controls the UTXOs.
    func fetchQBTCClaimableUtxos(
        bitcoinCoin: CoinMeta,
        address: String
    ) async throws -> [ClaimableUtxo] {
        let blockchair = try await fetchBlockchairData(coin: bitcoinCoin, address: address)
        return (blockchair.utxo ?? []).compactMap(ClaimableUtxo.init(blockchair:))
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
              let index = blockchair.index, index >= 0,
              let value = blockchair.value, value >= 0 else {
            return nil
        }
        self.init(txid: txid, vout: UInt32(index), amount: UInt64(value))
    }
}
