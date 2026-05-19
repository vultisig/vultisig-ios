//
//  KyberSwapAPI.swift
//  VultisigApp
//

import Foundation

enum KyberSwapAPI: TargetType {
    case routes(chain: String, params: RouteParams)
    case buildTransaction(chain: String, body: KyberSwapService.KyberSwapBuildRequest)

    struct RouteParams {
        let tokenIn: String
        let tokenOut: String
        let amountIn: String
        let saveGas: Bool
        let gasInclude: Bool
        let slippageTolerance: Int
        let affiliateBps: Int
        let sourceIdentifier: String?
        let referrerAddress: String?
    }

    private static let kyberBaseURL = URL(string: "https://aggregator-api.kyberswap.com")!

    var baseURL: URL { Self.kyberBaseURL }

    var path: String {
        switch self {
        case .routes(let chain, _):
            return "/\(chain)/api/v1/routes"
        case .buildTransaction(let chain, _):
            return "/\(chain)/api/v1/route/build"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .routes:
            return .get
        case .buildTransaction:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .routes(_, let params):
            var query: [String: Any] = [
                "tokenIn": params.tokenIn,
                "tokenOut": params.tokenOut,
                "amountIn": params.amountIn,
                "saveGas": params.saveGas,
                "gasInclude": params.gasInclude,
                "slippageTolerance": params.slippageTolerance
            ]
            if params.affiliateBps > 0,
               let sourceIdentifier = params.sourceIdentifier,
               let referrerAddress = params.referrerAddress {
                query["source"] = sourceIdentifier
                query["referral"] = referrerAddress
                query["feeAmount"] = params.affiliateBps
                query["chargeFeeBy"] = "currency_out"
                query["isInBps"] = true
                query["feeReceiver"] = referrerAddress
            }
            return .requestParameters(query, .urlEncoding)
        case .buildTransaction(_, let body):
            return .requestCodable(body, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        [
            "accept": "application/json",
            "content-type": "application/json",
            "x-client-id": KyberSwapService.sourceIdentifier
        ]
    }

    var validationType: ValidationType {
        switch self {
        case .routes, .buildTransaction:
            // KyberSwap returns structured error bodies (`code`, `message`,
            // `details`) with HTTP 400 for revert/allowance/funds issues; we
            // decode those to map to typed KyberSwapError cases.
            return .customCodes([200, 400])
        }
    }
}
