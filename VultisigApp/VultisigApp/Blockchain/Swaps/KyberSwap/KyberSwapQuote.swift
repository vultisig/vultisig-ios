//
//  KyberSwapQuote.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation
import BigInt

struct KyberSwapQuote: Codable, Hashable {
    struct Data: Codable, Hashable {
        let amountIn: String
        let amountInUsd: String
        let amountOut: String
        let amountOutUsd: String
        var gas: String
        let gasUsd: String
        let data: String
        let routerAddress: String
        let transactionValue: String
        var gasPrice: String?
    }

    let code: Int
    let message: String
    var data: Data
    let requestId: String

    var dstAmount: String {
        return data.amountOut
    }

    /// Returns the gas-limit estimate from KyberSwap's `routeSummary.gas`.
    /// KyberSwap pre-buffers this value to absorb pool-state shifts; no
    /// additional client-side multiplier is applied. Matches the SDK /
    /// Windows extension and Android KyberSwap mappings.
    var gas: Int64 {
        return Int64(data.gas) ?? Int64(EVMHelper.defaultETHSwapGasUnit)
    }

    /// Fallback gas price (1 gwei) applied only when the aggregator's
    /// `routeSummary.gasPrice` is missing or unparseable.
    static let fallbackGasPriceWei = BigInt("1000000000") ?? BigInt(0)

    /// Parses a KyberSwap-returned `gasPrice` string into wei. The fallback
    /// applies only when the input is unparseable; valid sub-gwei responses
    /// flow through unchanged.
    static func parseGasPriceWei(_ raw: String?) -> BigInt {
        guard let raw, let parsed = BigInt(raw) else { return fallbackGasPriceWei }
        return parsed
    }

    var tx: Transaction {

        return Transaction(
            from: "",
            to: data.routerAddress,
            data: data.data,
            value: data.transactionValue,
            gasPrice: data.gasPrice ?? "",
            gas: Int64(data.gas) ?? 0
        )
    }
}

extension KyberSwapQuote {
    struct Transaction: Codable, Hashable {
        let from: String
        let to: String
        let data: String
        let value: String
        let gasPrice: String
        let gas: Int64
    }
}
