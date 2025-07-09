//
//  CetusAggregatorService.swift
//  VultisigApp
//
//  Created by Assistant on current date.
//

import Foundation
import WalletCore
import BigInt

class CetusAggregatorService {
    static let shared = CetusAggregatorService()
    private init() {}
    
    // Cetus aggregator package information
    struct CetusPackages {
        static let aggregatorV2 = CetusPackage(
            name: "aggregator-v2",
            id: "0xeffc8ae61f439bb34c9b905ff8f29ec56873dcedf81c7123ff2f1f67c45ec302",
            publishedAt: "0x47a7b90756fba96fe649c2aaa10ec60dec6b8cb8545573d621310072721133aa",
            version: 12
        )
        
        static let aggregatorExtendV1 = CetusPackage(
            name: "aggregator-extend-v1",
            id: "0x43811be4677f5a5de7bf2dac740c10abddfaa524aee6b18e910eeadda8a2f6ae",
            publishedAt: "0x8093d002bba575f1378b0da206a8df1fc55c4b5b3718752304f1b67a505d2be4",
            version: 17
        )
        
        static let aggregatorExtendV2 = CetusPackage(
            name: "aggregator-extend-v2",
            id: "0x368d13376443a8051b22b42a9125f6a3bc836422bb2d9c4a53984b8d6624c326",
            publishedAt: "0x5cb7499fc49c2642310e24a4ecffdbee00133f97e80e2b45bca90c64d55de880",
            version: 9
        )
    }
    
    struct CetusPackage {
        let name: String
        let id: String
        let publishedAt: String
        let version: Int
    }
    
    private let baseURL = "https://api-sui.cetus.zone"
    private let jsonDecoder = JSONDecoder()
    
    /// Find routes for swapping tokens using Cetus aggregator
    /// - Parameters:
    ///   - fromToken: Source token address (use "0x2::sui::SUI" for native SUI)
    ///   - toToken: Destination token address (use USDC address for price calculation)
    ///   - amount: Amount to swap (in smallest units)
    /// - Returns: CetusRouteResponse containing swap routes and price information
    func findRoutes(fromToken: String, toToken: String, amount: String) async throws -> CetusRouteResponse {
        let url = URL(string: "\(baseURL)/router_v2/find_routes")!
        
        let requestBody: [String: Any] = [
            "from": fromToken,
            "to": toToken,
            "amount": amount,
            "by_amount_in": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Log response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Cetus aggregator response: \(jsonString)")
        }
        
        let response = try jsonDecoder.decode(CetusRouteResponse.self, from: data)
        return response
    }
    
    /// Get USD value for a SUI token using Cetus aggregator
    /// - Parameter contractAddress: The token contract address
    /// - Returns: Price in USD (0.0 if not found)
    func getTokenUSDValue(contractAddress: String) async -> Double {
        do {
            // USDC address on SUI
            let usdcAddress = "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC"
            
            // Amount: 1 token with appropriate decimals (we'll use 9 decimals as default for SUI tokens)
            // This will be adjusted based on actual token decimals
            let amount = "1000000000" // 1 token with 9 decimals
            
            // Try to find routes from token to USDC
            let routes = try await findRoutes(
                fromToken: contractAddress,
                toToken: usdcAddress,
                amount: amount
            )
            
            // Calculate price from the best route
            if let bestRoute = routes.routes.first,
               let amountOut = Double(bestRoute.amount_out),
               let amountIn = Double(amount) {
                
                // Since we're swapping to USDC (6 decimals), we need to adjust
                let usdcDecimals = 6
                let tokenDecimals = 9 // Default for SUI tokens, should be fetched from metadata
                
                let usdcAmount = amountOut / pow(10, Double(usdcDecimals))
                let tokenAmount = amountIn / pow(10, Double(tokenDecimals))
                
                // Price = USDC amount / Token amount
                let price = usdcAmount / tokenAmount
                
                return price > 0 ? price : 0.0
            }
            
            // If no direct route to USDC, try via SUI
            let suiAddress = "0x2::sui::SUI"
            
            // First get token -> SUI rate
            let tokenToSuiRoutes = try await findRoutes(
                fromToken: contractAddress,
                toToken: suiAddress,
                amount: amount
            )
            
            if let tokenToSuiRoute = tokenToSuiRoutes.routes.first,
               let suiAmountOut = Double(tokenToSuiRoute.amount_out) {
                
                // Then get SUI -> USDC rate
                let suiToUsdcRoutes = try await findRoutes(
                    fromToken: suiAddress,
                    toToken: usdcAddress,
                    amount: tokenToSuiRoute.amount_out
                )
                
                if let suiToUsdcRoute = suiToUsdcRoutes.routes.first,
                   let usdcAmountOut = Double(suiToUsdcRoute.amount_out),
                   let amountIn = Double(amount) {
                    
                    // Calculate final price
                    let usdcDecimals = 6
                    let tokenDecimals = 9
                    
                    let usdcAmount = usdcAmountOut / pow(10, Double(usdcDecimals))
                    let tokenAmount = amountIn / pow(10, Double(tokenDecimals))
                    
                    let price = usdcAmount / tokenAmount
                    
                    return price > 0 ? price : 0.0
                }
            }
            
            return 0.0
            
        } catch {
            print("Error fetching Cetus aggregator price for \(contractAddress): \(error.localizedDescription)")
            return 0.0
        }
    }
    
    /// Get token price with proper decimal handling
    /// - Parameters:
    ///   - contractAddress: Token contract address
    ///   - decimals: Token decimals
    /// - Returns: Price in USD
    func getTokenUSDValue(contractAddress: String, decimals: Int) async -> Double {
        do {
            let usdcAddress = "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC"
            
            // Amount: 1 token with proper decimals
            let amount = String(BigInt(10).power(decimals))
            
            let routes = try await findRoutes(
                fromToken: contractAddress,
                toToken: usdcAddress,
                amount: amount
            )
            
            if let bestRoute = routes.routes.first,
               let amountOut = Double(bestRoute.amount_out),
               let amountIn = Double(amount) {
                
                let usdcDecimals = 6
                
                let usdcAmount = amountOut / pow(10, Double(usdcDecimals))
                let tokenAmount = amountIn / pow(10, Double(decimals))
                
                let price = usdcAmount / tokenAmount
                
                return price > 0 ? price : 0.0
            }
            
            return 0.0
            
        } catch {
            print("Error fetching Cetus price with decimals for \(contractAddress): \(error.localizedDescription)")
            return 0.0
        }
    }
}

// MARK: - Response Models

struct CetusRouteResponse: Codable {
    let routes: [CetusRoute]
    let status: String?
    let message: String?
}

struct CetusRoute: Codable {
    let amount_in: String
    let amount_out: String
    let paths: [CetusPath]
    let is_exact_in: Bool
    let by_amount_in: Bool
    let split_percent: Double?
    let price_impact: Double?
}

struct CetusPath: Codable {
    let pool_id: String
    let from_coin: String
    let to_coin: String
    let direction: Bool
    let is_partner: Bool
    let partner_name: String?
    let amount_in: String
    let amount_out: String
} 
