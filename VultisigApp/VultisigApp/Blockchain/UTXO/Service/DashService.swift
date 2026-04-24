//
//  DashService.swift
//  VultisigApp
//

import Foundation

actor DashService {

    enum DashServiceError: Error {
        case rpcError(code: Int, message: String)
        case missingResult
    }

    static let shared = DashService()

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchUtxos(address: String) async throws -> [UtxoInfo] {
        let response = try await httpClient.request(
            DashRpcAPI.getAddressUtxos(addresses: [address]),
            responseType: DashRpcResponse<[DashUtxo]>.self
        )

        if let error = response.data.error {
            throw DashServiceError.rpcError(code: error.code, message: error.message)
        }

        guard let utxos = response.data.result else {
            throw DashServiceError.missingResult
        }

        return utxos.compactMap { utxo in
            guard utxo.outputIndex >= 0, let index = UInt32(exactly: utxo.outputIndex) else {
                return nil
            }
            return UtxoInfo(
                hash: utxo.txid,
                amount: utxo.satoshis,
                index: index
            )
        }
    }
}
