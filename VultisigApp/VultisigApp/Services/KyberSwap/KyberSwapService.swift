//
//  KyberSwapService.swift
//  VultisigApp
//
//  Created by AI Assistant on [Current Date].
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
        
        // First get the route summary
        let routeUrl = Endpoint.fetchKyberSwapRoute(
            chain: chain,
            tokenIn: sourceAddress,
            tokenOut: destinationAddress,
            amountIn: amount,
            saveGas: false,
            gasInclude: true,
            slippageTolerance: 50, // 0.5% in basis points
            isAffiliate: isAffiliate
        )
        
        var routeRequest = URLRequest(url: routeUrl)
        routeRequest.allHTTPHeaderFields = [
            "accept": "application/json",
            "content-type": "application/json"
        ]
        
        let (routeData, _) = try await URLSession.shared.data(for: routeRequest)
        let routeResponse = try JSONDecoder().decode(KyberSwapRouteResponse.self, from: routeData)
        
        // Now build the transaction
        let buildUrl = Endpoint.buildKyberSwapTransaction(chain: chain)
        
        let buildPayload = KyberSwapBuildRequest(
            routeSummary: routeResponse.data.routeSummary,
            sender: from,
            recipient: from,
            slippageTolerance: 50,
            deadline: Int(Date().timeIntervalSince1970) + 1200 // 20 minutes from now
        )
        
        var buildRequest = URLRequest(url: buildUrl)
        buildRequest.httpMethod = "POST"
        buildRequest.allHTTPHeaderFields = [
            "accept": "application/json",
            "content-type": "application/json"
        ]
        buildRequest.httpBody = try JSONEncoder().encode(buildPayload)
        
        let (buildData, _) = try await URLSession.shared.data(for: buildRequest)
        
        print(String(data: buildData, encoding: .utf8) ?? "No data")
        
        var buildResponse = try JSONDecoder().decode(KyberSwapQuote.self, from: buildData)
        
        // Add gas price from route response to the build response
        let gasPrice = routeResponse.data.routeSummary.gasPrice
        buildResponse.data.gasPrice = gasPrice
        
        // Calculate fee from route response
        let gas = BigInt(routeResponse.data.routeSummary.gas) ?? BigInt.zero
        let gasPriceValue = BigInt(gasPrice) ?? BigInt("20000000000") // Use provided gasPrice or 20 Gwei default
        let fee = gas * gasPriceValue
        
        return (buildResponse, fee)
    }
    
    func fetchTokens(chain: Chain) async throws -> [KyberSwapToken] {
        // Convert chain to chain ID like OneInch does
        let chainId = getChainId(for: chain)
        let url = Endpoint.fetchKyberSwapTokens(chainId: chainId)
        let response: KyberSwapTokensResponse = try await Utils.fetchObject(from: url.absoluteString)
        return response.data.tokens
    }
    
    func getChainId(for chain: Chain) -> String {
        switch chain {
        case .ethereum:
            return "1"
        case .bscChain:
            return "56"
        case .polygon:
            return "137"
        case .arbitrum:
            return "42161"
        case .avalanche:
            return "43114"
        case .optimism:
            return "10"
        case .base:
            return "8453"
        case .zksync:
            return "324"
        case .blast:
            return "81457"
        default:
            return "1" // Default to Ethereum
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
    
    // Helper for handling arbitrary JSON structures in poolExtra and extra
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
} 
