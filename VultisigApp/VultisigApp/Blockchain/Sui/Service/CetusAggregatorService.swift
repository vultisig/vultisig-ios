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

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Find routes for swapping tokens using Cetus aggregator
    /// - Parameters:
    ///   - fromToken: Source token address (use "0x2::sui::SUI" for native SUI)
    ///   - toToken: Destination token address (use USDC address for price calculation)
    ///   - amount: Amount to swap (in smallest units)
    /// - Returns: CetusRouteResponse containing swap routes and price information
    /// - Throws: NSError if HTTP request fails or API returns an error
    func findRoutes(fromToken: String, toToken: String, amount: String) async throws -> CetusRouteResponse {
        guard let amountValue = UInt64(amount) else {
            throw NSError(domain: "CetusAggregatorService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid amount format"])
        }

        let response = try await httpClient.request(
            CetusAPI.findRoutes(fromToken: fromToken, toToken: toToken, amount: amountValue),
            responseType: CetusAPIResponse.self
        )

        if response.data.code != 200 || response.data.data == nil {
            throw NSError(domain: "CetusAggregatorService", code: response.data.code, userInfo: [NSLocalizedDescriptionKey: response.data.msg])
        }

        guard let data = response.data.data else {
            throw NSError(domain: "CetusAggregatorService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data returned from API"])
        }

        return data
    }

    /// Get token price with proper decimal handling
    /// - Parameters:
    ///   - contractAddress: Token contract address
    ///   - decimals: Token decimals (defaults to 9 for SUI native tokens)
    /// - Returns: Price in USD
    func getTokenUSDValue(contractAddress: String, decimals: Int = 9) async -> Double {
        do {
            let usdcAddress = SuiConstants.usdcAddress

            // Amount: 1 token with proper decimals
            let amount = String(BigInt(10).power(decimals))

            let routes = try await findRoutes(
                fromToken: contractAddress,
                toToken: usdcAddress,
                amount: amount
            )

            if !routes.routes.isEmpty {
                let amountOut = Double(routes.amount_out) ?? 0
                let amountIn = Double(routes.amount_in) ?? 0

                let usdcDecimals = SuiConstants.usdcDecimals

                let usdcAmount = amountOut / pow(10, Double(usdcDecimals))
                let tokenAmount = amountIn / pow(10, Double(decimals))

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

            if !tokenToSuiRoutes.routes.isEmpty {
                let suiAmountOut = tokenToSuiRoutes.amount_out

                // Then get SUI -> USDC rate
                let suiToUsdcRoutes = try await findRoutes(
                    fromToken: suiAddress,
                    toToken: usdcAddress,
                    amount: suiAmountOut
                )

                if !suiToUsdcRoutes.routes.isEmpty {
                    let usdcAmountOut = Double(suiToUsdcRoutes.amount_out) ?? 0
                    let amountIn = Double(amount) ?? 0

                    // Calculate final price
                    let usdcAmount = usdcAmountOut / pow(10, Double(SuiConstants.usdcDecimals))
                    let tokenAmount = amountIn / pow(10, Double(decimals))

                    let price = tokenAmount > 0 ? usdcAmount / tokenAmount : 0

                    return price > 0 ? price : 0.0
                }
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
