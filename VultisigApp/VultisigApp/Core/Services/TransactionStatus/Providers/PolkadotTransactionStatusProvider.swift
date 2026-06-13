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
/// A bare Substrate node does not index extrinsics by hash, so status is derived
/// from the transaction pool: `author_pendingExtrinsics` returns the extrinsics
/// still awaiting inclusion. The submitted extrinsic hash is the blake2b-256 of
/// its SCALE-encoded bytes, so we hash each pending extrinsic and look for a match.
///
/// - Hash found in the pool → still `pending`.
/// - Hash absent → it has left the pool (included in a block) → `confirmed`.
///
/// Node RPC cannot replay an already-included extrinsic's events, so on-chain
/// dispatch failures are not distinguished here; the node rejects malformed or
/// invalid extrinsics at broadcast time (`author_submitExtrinsic`) instead.
struct PolkadotTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let response = try await httpClient.request(
            PolkadotTransactionStatusAPI.pendingExtrinsics,
            responseType: PolkadotTransactionStatusResponse.self
        ).data

        if let error = response.error {
            throw RpcServiceError.rpcError(code: error.code, message: error.message)
        }

        let pendingExtrinsics = response.result ?? []
        let targetHash = query.txHash.stripHexPrefix().lowercased()

        let isPending = pendingExtrinsics.contains { extrinsic in
            extrinsicHash(forHex: extrinsic) == targetHash
        }

        return TransactionStatusResult(
            status: isPending ? .pending : .confirmed,
            blockNumber: nil,
            confirmations: nil
        )
    }

    /// blake2b-256 of the SCALE-encoded extrinsic bytes, lowercased and without
    /// the `0x` prefix — the same value `author_submitExtrinsic` returns as the
    /// extrinsic hash. Returns `nil` for hex that cannot be decoded.
    private func extrinsicHash(forHex hex: String) -> String? {
        guard let bytes = Data(hexString: hex.stripHexPrefix()) else {
            return nil
        }
        return Hash.blake2b(data: bytes, size: 32).toHexString().lowercased()
    }
}
