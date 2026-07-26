//
//  QBTCProofService.swift
//  VultisigApp
//
//  Client for the QBTC proof service. The /prove call is long-running
//  (up to 5 minutes) — callers must surface progress UI.
//

import Foundation
import OSLog

final class QBTCProofService {
    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-proof")

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Generates a PLONK proof of UTXO ownership. Long-running.
    /// The returned hashes are byte-equal to what `QBTCClaimHashes.computeAll`
    /// would produce — they MAY be used directly when assembling
    /// `MsgClaimWithProof`.
    func generateProof(_ request: ClaimProofRequest) async throws -> ClaimProofResponse {
        logger.info("Requesting QBTC claim proof for \(request.utxos.count) UTXO(s)")
        let response = try await httpClient.request(
            QBTCProofServiceAPI.prove(request),
            responseType: ClaimProofResponse.self
        )
        return response.data
    }
}
