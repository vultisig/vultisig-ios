//
//  ZcashRpcModels.swift
//  VultisigApp
//
//  Decodes the Zcash `getblockchaininfo` JSON-RPC response. Only the
//  `consensus.nextblock` branch id is consumed; every other field the node
//  returns is ignored by the decoder.
//

import Foundation

struct ZcashBlockchainInfoResponse: Decodable {
    let result: ZcashBlockchainInfoResult?
}

struct ZcashBlockchainInfoResult: Decodable {
    let consensus: ZcashConsensus?
}

struct ZcashConsensus: Decodable {
    /// Branch id active for the chain tip (big-endian hex).
    let chaintip: String?
    /// Branch id active for the next block (big-endian hex, e.g. `5437f330`);
    /// the value signing must use so a tx mined after an upcoming upgrade is
    /// still accepted.
    let nextblock: String?
}
