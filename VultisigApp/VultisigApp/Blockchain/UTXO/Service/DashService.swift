//
//  DashService.swift
//  VultisigApp
//

import Foundation

actor DashService {

    static let shared = DashService()

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private init() {}

    func fetchUtxos(address: String) async throws -> [UtxoInfo] {
        let body = DashRpcRequest(
            method: "getaddressutxos",
            params: [["addresses": [address]]]
        )

        var request = URLRequest(url: Endpoint.dashRpc())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try Self.decoder.decode(DashRpcResponse<[DashUtxo]>.self, from: data)

        if let error = decoded.error {
            print("Dash RPC error (\(error.code)): \(error.message)")
            return []
        }

        guard let utxos = decoded.result else {
            return []
        }

        return utxos.map { utxo in
            UtxoInfo(
                hash: utxo.txid,
                amount: utxo.satoshis,
                index: UInt32(utxo.outputIndex)
            )
        }
    }
}

// MARK: - Models

private struct DashRpcRequest: Encodable {
    let jsonrpc: String = "1.0"
    let id: String = "vultisig"
    let method: String
    let params: [[String: [String]]]
}

private struct DashRpcResponse<T: Decodable>: Decodable {
    let result: T?
    let error: DashRpcError?
    let id: String?
}

private struct DashRpcError: Decodable {
    let code: Int
    let message: String
}

private struct DashUtxo: Decodable {
    let address: String
    let txid: String
    let outputIndex: Int
    let script: String
    let satoshis: Int64
    let height: Int
}
