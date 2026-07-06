//
//  1InchService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation
import BigInt

struct OneInchService {

    static let shared = OneInchService()
    static let referredFee = 0.5

    private let httpClient: HTTPClientProtocol = HTTPClient()

    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }

    private var referrerAddress: String {
        return "0x8E247a480449c84a5fDD25974A8501f3EFa4ABb9"
    }

    private var supportedChain: [Chain] {
        return [
            .ethereum, .arbitrum, .avalanche, .bscChain, .solana, .optimism, .polygon, .polygonV2, .zksync, .base
        ]
    }
    func isChainSupported(chain: Chain) -> Bool {
        return supportedChain.contains(chain)
    }
    func fetchQuotes(
        chain: String,
        source: String,
        destination: String,
        amount: String,
        from: String,
        isAffiliate: Bool,
        vultTierDiscount: Int,
        slippageBps: Int? = nil
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {

        let sourceAddress = source.isEmpty ? nullAddress : source
        let destinationAddress = destination.isEmpty ? nullAddress : destination

        // 1inch takes slippage as a percent string and accepts only 0–50%
        // (0–5000 bps). `Auto` (nil) keeps the existing 0.5% default; a custom
        // value is clamped into range before bps → percent conversion so an
        // out-of-bounds input never triggers an avoidable quote failure.
        let slippageValue = slippageBps
            .map { min(max($0, 0), 5000) }
            .map { Self.percentString(fromBps: $0) } ?? "0.5"

        let params = OneInchAPI.SwapParams(
            source: sourceAddress,
            destination: destinationAddress,
            amount: amount,
            from: from,
            slippage: slippageValue,
            referrer: referrerAddress,
            fee: isAffiliate ? bps(for: vultTierDiscount) : 0
        )

        do {
            let response = try await httpClient.request(
                OneInchAPI.swap(chain: chain, params: params),
                responseType: EVMQuote.self
            )

            let quote = response.data
            let gasPrice = BigInt(quote.tx.gasPrice) ?? 0
            let gas = BigInt(quote.tx.gas)
            let fee = gas * gasPrice

            return (quote, fee)
        } catch HTTPError.statusCode(_, let data) {
            if let data, let error = try? JSONDecoder().decode(OneInchQuoteError.self, from: data) {
                throw HelperError.runtimeError(error.description)
            }
            throw HelperError.runtimeError("1inch swap request failed")
        }
    }

    func fetchTokens(chain: Int) async throws -> [OneInchToken] {
        let response = try await httpClient.request(
            OneInchAPI.tokens(chain: chain),
            responseType: OneInchTokensResponse.self
        )
        return Array(response.data.tokens.values)
    }

    /// Fetch the ERC-20 balance map for an address. Returns a dictionary keyed
    /// on lowercased contract address; values are decimal strings of base-unit
    /// balances. Used by the EVM coin-finder to skip the per-token RPC call
    /// for tokens the address doesn't actually hold.
    func fetchBalances(chain: Int, address: String) async throws -> [String: String] {
        let response = try await httpClient.request(
            OneInchAPI.balances(chain: chain, address: address),
            responseType: [String: String].self
        )
        return response.data
    }

    /// Bulk metadata lookup for a set of contract addresses. The response is
    /// keyed on contract address (lowercased). Used by the EVM coin-finder
    /// after `fetchBalances` to resolve symbol/decimals/logo for the address's
    /// actual holdings.
    func fetchCustomTokens(chain: Int, addresses: [String]) async throws -> [String: OneInchToken] {
        guard !addresses.isEmpty else { return [:] }
        let response = try await httpClient.request(
            OneInchAPI.customTokens(chain: chain, addresses: addresses),
            responseType: [String: OneInchToken].self
        )
        return response.data
    }

    func bps(for discount: Int) -> Double {
        let formattedDiscount = Double(discount) / 100.0
        return max(0, Self.referredFee - formattedDiscount)
    }

    /// Convert a basis-points slippage to the percent string 1inch expects
    /// (e.g. 50 bps → "0.5", 300 bps → "3"), trimming trailing zeros.
    static func percentString(fromBps bps: Int) -> String {
        let percent = Decimal(bps) / 100
        let number = NSDecimalNumber(decimal: percent)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter.string(from: number) ?? "\(percent)"
    }
}
