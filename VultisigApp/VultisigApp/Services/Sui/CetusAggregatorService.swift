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
    
    private let baseURL: String
    private let jsonDecoder = JSONDecoder()
    
    init(baseURL: String = Endpoint.cetusApiBase) {
        self.baseURL = baseURL
    }
    
    /// Find routes for swapping tokens using Cetus aggregator
    /// - Parameters:
    ///   - fromToken: Source token address (use "0x2::sui::SUI" for native SUI)
    ///   - toToken: Destination token address (use USDC address for price calculation)
    ///   - amount: Amount to swap (in smallest units)
    /// - Returns: CetusRouteResponse containing swap routes and price information
    /// - Throws: NSError if HTTP request fails or API returns an error
    func findRoutes(fromToken: String, toToken: String, amount: String) async throws -> CetusRouteResponse {
        let url = URL(string: "\(baseURL)/router_v2/find_routes")!
        
        // Convert amount string to UInt64 for API
        guard let amountValue = UInt64(amount) else {
            throw NSError(domain: "CetusAggregatorService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid amount format"])
        }
        
        let requestBody: [String: Any] = [
            "from": fromToken,
            "target": toToken,  // Changed from "to" to "target"
            "amount": amountValue,
            "by_amount_in": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate HTTP response status
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "CetusAggregatorService", 
                          code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
        }
        
        let apiResponse = try jsonDecoder.decode(CetusAPIResponse.self, from: data)
        
        // Check if the API returned an error or no data
        if apiResponse.code != 200 || apiResponse.data == nil {
            throw NSError(domain: "CetusAggregatorService", code: apiResponse.code, userInfo: [NSLocalizedDescriptionKey: apiResponse.msg])
        }
        
        guard let data = apiResponse.data else {
            throw NSError(domain: "CetusAggregatorService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data returned from API"])
        }
        
        return data
    }
    
    /// Get USD value for a SUI token using Cetus aggregator
    /// - Parameter contractAddress: The token contract address
    /// - Returns: Price in USD (0.0 if not found)
    /// - Warning: This method assumes 9 decimals for all tokens which may be incorrect. Use getTokenUSDValue(contractAddress:decimals:) instead.
    @available(*, deprecated, message: "Use getTokenUSDValue(contractAddress:decimals:) instead to provide accurate decimals")
    func getTokenUSDValue(contractAddress: String) async -> Double {
        do {
            // USDC address on SUI
            let usdcAddress = SuiConstants.usdcAddress
            
            // WARNING: This assumes 9 decimals which may not be correct for all tokens
            // The caller should provide the actual decimals
            let amount = "1000000000" // 1 token with 9 decimals
            
            // Try to find routes from token to USDC
            let routes = try await findRoutes(
                fromToken: contractAddress,
                toToken: usdcAddress,
                amount: amount
            )
            
            // Calculate price from the response
            if routes.routes.count > 0 {
                let amountOut = Double(routes.amount_out) ?? 0
                let amountIn = Double(routes.amount_in) ?? 0
                
                // Since we're swapping to USDC (6 decimals), we need to adjust
                let usdcDecimals = SuiConstants.usdcDecimals
                let tokenDecimals = SuiConstants.defaultDecimals // Default for SUI tokens, should be fetched from metadata
                
                let usdcAmount = amountOut / pow(10, Double(usdcDecimals))
                let tokenAmount = amountIn / pow(10, Double(tokenDecimals))
                
                // Price = USDC amount / Token amount
                let price = tokenAmount > 0 ? usdcAmount / tokenAmount : 0
                
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
            
            if tokenToSuiRoutes.routes.count > 0 {
                let suiAmountOut = tokenToSuiRoutes.amount_out
                
                // Then get SUI -> USDC rate
                let suiToUsdcRoutes = try await findRoutes(
                    fromToken: suiAddress,
                    toToken: usdcAddress,
                    amount: suiAmountOut
                )
                
                if suiToUsdcRoutes.routes.count > 0 {
                    let usdcAmountOut = Double(suiToUsdcRoutes.amount_out) ?? 0
                    let amountIn = Double(amount) ?? 0
                    
                    // Calculate final price
                    let usdcDecimals = 6
                    let tokenDecimals = 9
                    
                    let usdcAmount = usdcAmountOut / pow(10, Double(usdcDecimals))
                    let tokenAmount = amountIn / pow(10, Double(tokenDecimals))
                    
                    let price = tokenAmount > 0 ? usdcAmount / tokenAmount : 0
                    
                    return price > 0 ? price : 0.0
                }
            }
            
            return 0.0
            
        } catch {
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
            let usdcAddress = SuiConstants.usdcAddress
            
            // Amount: 1 token with proper decimals
            let amount = String(BigInt(10).power(decimals))
            
            let routes = try await findRoutes(
                fromToken: contractAddress,
                toToken: usdcAddress,
                amount: amount
            )
            
            if routes.routes.count > 0 {
                let amountOut = Double(routes.amount_out) ?? 0
                let amountIn = Double(routes.amount_in) ?? 0
                
                let usdcDecimals = 6
                
                let usdcAmount = amountOut / pow(10, Double(usdcDecimals))
                let tokenAmount = amountIn / pow(10, Double(decimals))
                
                let price = tokenAmount > 0 ? usdcAmount / tokenAmount : 0
                
                return price > 0 ? price : 0.0
            }
            
            return 0.0
            
        } catch {
            return 0.0
        }
    }
}

// MARK: - Response Models

struct CetusAPIResponse: Codable {
    let code: Int
    let msg: String
    let data: CetusRouteResponse?
}

struct CetusRouteResponse: Codable {
    let request_id: String?
    let amount_in: String
    let amount_out: String
    let deviation_ratio: String?
    let routes: [CetusRoute]
    let gas: Int?
    
    enum CodingKeys: String, CodingKey {
        case request_id, amount_in, amount_out, deviation_ratio, routes, gas
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        request_id = try container.decodeIfPresent(String.self, forKey: .request_id)
        
        // Handle amount_in as either String or Int
        if let intValue = try? container.decode(Int.self, forKey: .amount_in) {
            amount_in = String(intValue)
        } else {
            amount_in = try container.decode(String.self, forKey: .amount_in)
        }
        
        // Handle amount_out as either String or Int
        if let intValue = try? container.decode(Int.self, forKey: .amount_out) {
            amount_out = String(intValue)
        } else {
            amount_out = try container.decode(String.self, forKey: .amount_out)
        }
        
        deviation_ratio = try container.decodeIfPresent(String.self, forKey: .deviation_ratio)
        routes = try container.decode([CetusRoute].self, forKey: .routes)
        gas = try container.decodeIfPresent(Int.self, forKey: .gas)
    }
}

struct CetusRoute: Codable {
    let path: [CetusPath]
    let amount_in: String
    let amount_out: String
    let initial_price: String
    
    enum CodingKeys: String, CodingKey {
        case path, amount_in, amount_out, initial_price
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        path = try container.decode([CetusPath].self, forKey: .path)
        
        // Handle amount_in as either String or Int
        if let intValue = try? container.decode(Int.self, forKey: .amount_in) {
            amount_in = String(intValue)
        } else {
            amount_in = try container.decode(String.self, forKey: .amount_in)
        }
        
        // Handle amount_out as either String or Int
        if let intValue = try? container.decode(Int.self, forKey: .amount_out) {
            amount_out = String(intValue)
        } else {
            amount_out = try container.decode(String.self, forKey: .amount_out)
        }
        
        initial_price = try container.decode(String.self, forKey: .initial_price)
    }
}

struct CetusPath: Codable {
    let id: String
    let provider: String
    let from: String
    let target: String
    let direction: Bool
    let fee_rate: String
    let lot_size: Int
    let amount_in: String
    let amount_out: String
    let extended_details: CetusExtendedDetails?
    
    enum CodingKeys: String, CodingKey {
        case id, provider, from, target, direction, fee_rate, lot_size, amount_in, amount_out, extended_details
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(String.self, forKey: .provider)
        from = try container.decode(String.self, forKey: .from)
        target = try container.decode(String.self, forKey: .target)
        direction = try container.decode(Bool.self, forKey: .direction)
        fee_rate = try container.decode(String.self, forKey: .fee_rate)
        lot_size = try container.decode(Int.self, forKey: .lot_size)
        
        // Handle amount_in as either String or Int
        if let intValue = try? container.decode(Int.self, forKey: .amount_in) {
            amount_in = String(intValue)
        } else {
            amount_in = try container.decode(String.self, forKey: .amount_in)
        }
        
        // Handle amount_out as either String or Int
        if let intValue = try? container.decode(Int.self, forKey: .amount_out) {
            amount_out = String(intValue)
        } else {
            amount_out = try container.decode(String.self, forKey: .amount_out)
        }
        
        extended_details = try container.decodeIfPresent(CetusExtendedDetails.self, forKey: .extended_details)
    }
}

struct CetusExtendedDetails: Codable {
    let after_sqrt_price: String
    
    enum CodingKeys: String, CodingKey {
        case after_sqrt_price
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle after_sqrt_price as either String or very large numbers
        // The API sometimes returns numbers too large for Int64
        do {
            // First try as String
            after_sqrt_price = try container.decode(String.self, forKey: .after_sqrt_price)
        } catch {
            // If that fails, decode as Decimal and convert to String
            // This handles very large numbers that don't fit in Int64
            if let decimalValue = try? container.decode(Decimal.self, forKey: .after_sqrt_price) {
                after_sqrt_price = "\(decimalValue)"
            } else {
                throw error
            }
        }
    }
} 
