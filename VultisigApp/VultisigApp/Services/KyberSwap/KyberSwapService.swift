//
//  KyberSwapService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation
import BigInt

struct KyberSwapService {
    
    static let shared = KyberSwapService()
    
    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
    
    func fetchQuotes(chain: String, source: String, destination: String, amount: String, from: String, isAffiliate: Bool) async throws -> (quote: KyberSwapQuote, fee: BigInt?) {
        
        let sourceAddress = source.isEmpty ? nullAddress : source
        let destinationAddress = destination.isEmpty ? nullAddress : destination
        
        let routeUrl = Endpoint.fetchKyberSwapRoute(
            chain: chain,
            tokenIn: sourceAddress,
            tokenOut: destinationAddress,
            amountIn: amount,
            saveGas: false,
            gasInclude: true,
            slippageTolerance: 100,
            isAffiliate: isAffiliate
        )
        
        var routeRequest = URLRequest(url: routeUrl)
        routeRequest.allHTTPHeaderFields = [
            "accept": "application/json",
            "content-type": "application/json"
        ]
        
        let (routeData, _) = try await URLSession.shared.data(for: routeRequest)
        
        if let errorResponse = try? JSONDecoder().decode(KyberSwapErrorResponse.self, from: routeData) {
            if errorResponse.code != 0 {
                throw KyberSwapError.apiError(code: errorResponse.code, message: errorResponse.message, details: errorResponse.details)
            }
        }
        
        let routeResponse = try JSONDecoder().decode(KyberSwapRouteResponse.self, from: routeData)
        let buildUrl = Endpoint.buildKyberSwapTransaction(chain: chain)
        
        let buildPayload = KyberSwapBuildRequest(
            routeSummary: routeResponse.data.routeSummary,
            sender: from,
            recipient: from,
            slippageTolerance: 100,
            deadline: Int(Date().timeIntervalSince1970) + 1200
        )
        
        var buildRequest = URLRequest(url: buildUrl)
        buildRequest.httpMethod = "POST"
        buildRequest.allHTTPHeaderFields = [
            "accept": "application/json",
            "content-type": "application/json"
        ]
        buildRequest.httpBody = try JSONEncoder().encode(buildPayload)
        
        let (buildData, _) = try await URLSession.shared.data(for: buildRequest)
        
        if let errorResponse = try? JSONDecoder().decode(KyberSwapErrorResponse.self, from: buildData) {
            if errorResponse.code != 0 {
                throw KyberSwapError.apiError(code: errorResponse.code, message: errorResponse.message, details: errorResponse.details)
            }
        }
        
        var buildResponse = try JSONDecoder().decode(KyberSwapQuote.self, from: buildData)
        
        let gasPrice = routeResponse.data.routeSummary.gasPrice
        buildResponse.data.gasPrice = gasPrice
        
        let baseGas = BigInt(buildResponse.data.gas) ?? BigInt.zero
                
        let gasMultiplierTimes10: Int
        switch chain {
        case "ethereum":
            gasMultiplierTimes10 = 14
        case "arbitrum", "optimism", "base", "polygon", "avalanche", "bsc":
            gasMultiplierTimes10 = 20
        default:
            gasMultiplierTimes10 = 16
        }
        
        let gas = (baseGas * BigInt(gasMultiplierTimes10)) / BigInt(10)
        
        let finalGas: BigInt
        if gas.isZero {
            finalGas = BigInt(EVMHelper.defaultETHSwapGasUnit)
        } else {
            finalGas = gas
        }
        
        let gasPriceValue = BigInt(gasPrice) ?? BigInt("20000000000")
        let minGasPrice = BigInt("1000000000")
        let finalGasPrice = gasPriceValue < minGasPrice ? minGasPrice : gasPriceValue
        
        let fee = finalGas * finalGasPrice
        
        return (buildResponse, fee)
    }
    
    func fetchTokens(chain: Chain) async throws -> [KyberSwapToken] {
        let chainName = getChainName(for: chain)
        let url = Endpoint.fetchKyberSwapTokens(chainId: chainName)
        let response: KyberSwapTokensResponse = try await Utils.fetchObject(from: url.absoluteString)
        return response.data.tokens
    }
    
    func getChainName(for chain: Chain) -> String {
        switch chain {
        case .ethereum:
            return "ethereum"
        case .bscChain:
            return "bsc"
        case .polygon:
            return "polygon"
        case .arbitrum:
            return "arbitrum"
        case .avalanche:
            return "avalanche"
        case .optimism:
            return "optimism"
        case .base:
            return "base"
        case .zksync:
            return "zksync"
        case .blast:
            return "blast"
        default:
            return "ethereum"
        }
    }
}

// MARK: - Support Types
private extension KyberSwapService {
    
    struct KyberSwapRouteResponse: Codable {
        let code: Int
        let message: String
        let data: RouteData
        let requestId: String
        
        struct RouteData: Codable {
            let routeSummary: RouteSummary
            let routerAddress: String
        }
        
        struct RouteSummary: Codable {
            let tokenIn: String
            let amountIn: String
            let amountInUsd: String
            let tokenOut: String
            let amountOut: String
            let amountOutUsd: String
            let gas: String
            let gasPrice: String
            let gasUsd: String
            let l1FeeUsd: String?
            let extraFee: ExtraFee?
            let route: [[RouteStep]]
            let routeID: String
            let checksum: String
            let timestamp: Int
            
            struct ExtraFee: Codable {
                let feeAmount: String
                let chargeFeeBy: String
                let isInBps: Bool
                let feeReceiver: String
            }
            
            struct RouteStep: Codable {
                let pool: String
                let tokenIn: String
                let tokenOut: String
                let swapAmount: String
                let amountOut: String
                let exchange: String
                let poolType: String
                let poolExtra: AnyCodable?
                let extra: AnyCodable?
            }
        }
    }
    
    struct AnyCodable: Codable {
        let value: Any
        
        init(_ value: Any) {
            self.value = value
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                value = intVal
            } else if let doubleVal = try? container.decode(Double.self) {
                value = doubleVal
            } else if let stringVal = try? container.decode(String.self) {
                value = stringVal
            } else if let boolVal = try? container.decode(Bool.self) {
                value = boolVal
            } else if let arrayVal = try? container.decode([AnyCodable].self) {
                value = arrayVal.map { $0.value }
            } else if let dictVal = try? container.decode([String: AnyCodable].self) {
                value = dictVal.mapValues { $0.value }
            } else {
                value = NSNull()
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let intVal = value as? Int {
                try container.encode(intVal)
            } else if let doubleVal = value as? Double {
                try container.encode(doubleVal)
            } else if let stringVal = value as? String {
                try container.encode(stringVal)
            } else if let boolVal = value as? Bool {
                try container.encode(boolVal)
            } else {
                try container.encodeNil()
            }
        }
    }
    
    struct KyberSwapBuildRequest: Codable {
        let routeSummary: KyberSwapRouteResponse.RouteSummary
        let sender: String
        let recipient: String
        let slippageTolerance: Int
        let deadline: Int
    }
    
    struct KyberSwapTokensResponse: Codable {
        let data: TokensData
        
        struct TokensData: Codable {
            let tokens: [KyberSwapToken]
        }
    }
    
    struct KyberSwapErrorResponse: Codable {
        let code: Int
        let message: String
        let details: String?
        let requestId: String?
    }
}

enum KyberSwapError: Error, LocalizedError {
    case apiError(code: Int, message: String, details: String?)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let code, let message, let details):
            let detailsStr = details?.isEmpty == false ? " - \(details!)" : ""
            return "KyberSwap API Error \(code): \(message)\(detailsStr)"
        }
    }
} 
