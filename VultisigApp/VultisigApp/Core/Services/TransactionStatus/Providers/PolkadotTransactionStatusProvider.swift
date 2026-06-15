//
//  PolkadotTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation
import WalletCore

/// Polkadot Asset Hub transaction status via node RPC.
///
/// A bare Substrate node does not index extrinsics by hash, so inclusion is
/// proven by scanning blocks: starting from the best head, walk back along
/// `parentHash` and blake2b-256 each block's extrinsics, looking for a match.
/// The hash is the same value `author_submitExtrinsic` returns. This reads real
/// blocks rather than the node-local mempool, so it stays correct behind the
/// load-balanced proxy.
///
/// - Hash found in a scanned block → `confirmed`.
/// - Not found within the scan window → `pending` (the poll loop retries).
///
/// The walk is bounded to one mortal era (`PolkadotHelper` builds extrinsics
/// with `period = 64`): beyond that window a mortal extrinsic can no longer be
/// included, and the bound covers the foreground poll window for Polkadot
/// (`ChainStatusConfig` caps it at 5 minutes ≈ 50 blocks at 6s/block). A
/// long-delayed check whose inclusion block has fallen outside the window stays
/// `pending` until the poll times out rather than being read from an indexer.
struct PolkadotTransactionStatusProvider: TransactionStatusProvider {
    /// One mortal era (`period = 64`). The signed extrinsic can only be included
    /// within this many blocks of its checkpoint, so scanning further back can
    /// never find it; it also bounds the walk on a genuinely pending/dropped tx.
    private static let maxScanDepth = 64

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let targetHash = query.txHash.stripHexPrefix().lowercased()
        guard !targetHash.isEmpty else {
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        }

        let isConfirmed = try await isExtrinsicInChain(targetHash: targetHash)
        return TransactionStatusResult(
            status: isConfirmed ? .confirmed : .pending,
            blockNumber: nil,
            confirmations: nil
        )
    }

    /// Walks the best chain from the head along `parentHash`, up to
    /// `maxScanDepth` blocks, returning `true` as soon as a block contains an
    /// extrinsic whose hash matches `targetHash`. A block that fails to load
    /// ends the walk (returns `false`) so the surrounding poll keeps retrying
    /// rather than declaring a terminal state on a transient RPC gap.
    private func isExtrinsicInChain(targetHash: String) async throws -> Bool {
        var blockHash: String?
        var scanned = 0

        while scanned < Self.maxScanDepth {
            guard let block = try await fetchBlock(blockHash: blockHash) else {
                return false
            }
            if block.extrinsics.contains(where: { extrinsicHash(forHex: $0) == targetHash }) {
                return true
            }
            blockHash = block.header.parentHash
            scanned += 1
        }
        return false
    }

    /// Fetches a block by hash (or the best head when `blockHash` is `nil`).
    /// Throws on an explicit RPC error; returns `nil` when the node has no block
    /// for the hash (end of the walk).
    private func fetchBlock(blockHash: String?) async throws -> PolkadotTransactionStatusResponse.PolkadotBlock? {
        let response = try await httpClient.request(
            PolkadotTransactionStatusAPI.getBlock(blockHash: blockHash),
            responseType: PolkadotTransactionStatusResponse.self
        ).data

        if let error = response.error {
            throw RpcServiceError.rpcError(code: error.code, message: error.message)
        }
        return response.result?.block
    }

    /// blake2b-256 of the SCALE-encoded extrinsic bytes, lowercased and without
    /// the `0x` prefix — the canonical Substrate extrinsic hash. Returns `nil`
    /// for hex that cannot be decoded.
    private func extrinsicHash(forHex hex: String) -> String? {
        guard let bytes = Data(hexString: hex.stripHexPrefix()) else {
            return nil
        }
        return Hash.blake2b(data: bytes, size: 32).toHexString().lowercased()
    }
}
