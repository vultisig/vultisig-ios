//
//  BittensorTransactionStatusResponse.swift
//  VultisigApp
//

import Foundation

/// Response shape from the Vultisig tao-tx proxy. The Taostats payload
/// nests the extrinsic record(s) under `data`; each entry carries an
/// optional `success` flag and `block_number`. An empty `data` array
/// means the chain hasn't seen the hash yet (still pending).
struct BittensorTransactionStatusResponse: Codable {
    let data: [Extrinsic]

    struct Extrinsic: Codable {
        let success: Bool?
        let blockNumber: Int?

        enum CodingKeys: String, CodingKey {
            case success
            case blockNumber = "block_number"
        }
    }
}
