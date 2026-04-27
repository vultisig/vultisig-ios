//
//  LiFiAPI.swift
//  VultisigApp
//

import Foundation

enum LiFiAPI: TargetType {
    case quote(params: QuoteParams)

    struct QuoteParams {
        let fromChain: String
        let toChain: String
        let fromToken: String
        let toToken: String
        let fromAmount: String
        let fromAddress: String
        let toAddress: String
        /// Integrator identifier only attached when the source coin supports
        /// LI.FI integrator fees; `nil` otherwise so we don't send an empty
        /// param.
        let integrator: String?
        /// Fee rate (e.g. "0.005") appended alongside `integrator`; both must
        /// be set together to register the fee with LI.FI.
        let fee: String?
    }

    private static let lifiBaseURL = URL(string: "https://li.quest")!

    var baseURL: URL { Self.lifiBaseURL }

    var path: String { "/v1/quote" }

    var method: HTTPMethod { .get }

    var task: HTTPTask {
        switch self {
        case .quote(let params):
            var query: [String: Any] = [
                "fromChain": params.fromChain,
                "toChain": params.toChain,
                "fromToken": params.fromToken,
                "toToken": params.toToken,
                "fromAmount": params.fromAmount,
                "fromAddress": params.fromAddress,
                "toAddress": params.toAddress
            ]
            if let integrator = params.integrator {
                query["integrator"] = integrator
            }
            if let fee = params.fee {
                query["fee"] = fee
            }
            return .requestParameters(query, .urlEncoding)
        }
    }
}
