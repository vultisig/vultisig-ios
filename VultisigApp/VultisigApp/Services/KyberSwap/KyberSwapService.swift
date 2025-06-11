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
            slippageTolerance: 100, // 1.0% in basis points (increased from 50 for better execution)
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
            slippageTolerance: 100, // 1.0% to match route request
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
        
        // Calculate fee using the SAME gas source as the transaction construction
        // Use build response gas (more accurate) instead of route response gas
        let baseGas = BigInt(buildResponse.data.gas) ?? BigInt.zero
        
        // Add debug logging to diagnose zero fee issue
        print("🔍 KyberSwap Fee Debug:")
        print("   Route Gas: '\(routeResponse.data.routeSummary.gas)'")
        print("   Build Gas: '\(buildResponse.data.gas)'")
        print("   GasPrice from API: '\(gasPrice)'")
        print("   BaseGas parsed: \(baseGas)")
        
        // Chain-specific gas buffer based on gas costs and execution characteristics
        // Ethereum: Expensive gas, conservative buffer
        // L2s: Cheap gas, can afford larger buffer for complex routing
        let gasMultiplier: Double
        switch chain {
        case "ethereum":
            gasMultiplier = 1.4 // 40% buffer - conservative for expensive Ethereum gas
        case "arbitrum", "optimism", "base", "polygon", "avalanche", "bsc":
            gasMultiplier = 2.0 // 100% buffer - L2s have cheap gas and complex routing
        default:
            gasMultiplier = 1.6 // 60% buffer - reasonable default for other chains
        }
        
        // Add debug logging to show chain-specific buffer
        print("   Chain: \(chain)")
        print("   Gas Multiplier: \(gasMultiplier)x")
        
        // Apply chain-specific gas buffer
        let gasBuffer = Double(baseGas.description) ?? 0.0
        let bufferedGasAmount = gasBuffer * gasMultiplier
        let gas = BigInt(bufferedGasAmount)
        
        // If gas is still zero after calculation, use a reasonable default for EVM swaps
        let finalGas: BigInt
        if gas.isZero {
            finalGas = BigInt(EVMHelper.defaultETHSwapGasUnit) // Use same default as transaction construction
            print("   ⚠️  Using fallback gas limit: \(finalGas)")
        } else {
            finalGas = gas
        }
        
        let gasPriceValue = BigInt(gasPrice) ?? BigInt("20000000000") // Use provided gasPrice or 20 Gwei default
        
        // Ensure minimum gas price of 1 GWEI (1,000,000,000 wei)
        let minGasPrice = BigInt("1000000000") // 1 GWEI minimum
        let finalGasPrice = gasPriceValue < minGasPrice ? minGasPrice : gasPriceValue
        
        let fee = finalGas * finalGasPrice
        
        print("   Buffered Gas: \(gas)")
        print("   Final Gas Used: \(finalGas)")
        print("   Gas Price Value: \(gasPriceValue)")
        print("   Final Gas Price (min 1 GWEI): \(finalGasPrice)")
        print("   Calculated Fee: \(fee)")
        print("🔍 End Debug")
        
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
        // KyberSwap API uses chain names, not chain IDs in the URL path
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
            return "ethereum" // Default to Ethereum
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
