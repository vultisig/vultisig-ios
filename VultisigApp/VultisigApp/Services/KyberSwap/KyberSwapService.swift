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

    static let sourceIdentifier = "vultisig-ios"
    static let referrerAddress = "0x8E247a480449c84a5fDD25974A8501f3EFa4ABb9"

    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }

    func fetchQuotes(chain: String, source: String, destination: String, amount: String, from: String, isAffiliate: Bool) async throws -> (quote: EVMQuote, fee: BigInt?) {

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
            isAffiliate: isAffiliate,
            sourceIdentifier: isAffiliate ? KyberSwapService.sourceIdentifier : nil,
            referrerAddress: isAffiliate ? KyberSwapService.referrerAddress : nil
        )

        var routeRequest = URLRequest(url: routeUrl)
        routeRequest.allHTTPHeaderFields = [
            "accept": "application/json",
            "content-type": "application/json",
            "x-client-id": KyberSwapService.sourceIdentifier
        ]

        let (routeData, _) = try await URLSession.shared.data(for: routeRequest)

        if let errorResponse = try? JSONDecoder().decode(KyberSwapErrorResponse.self, from: routeData) {
            if errorResponse.code != 0 {
                throw KyberSwapError.apiError(code: errorResponse.code, message: errorResponse.message, details: errorResponse.details)
            }
        }

        let routeResponse = try JSONDecoder().decode(KyberSwapRouteResponse.self, from: routeData)

        // Try with gas estimation first, retry without if TransferHelper error occurs
        return try await buildTransactionWithFallback(
            chain: chain,
            routeResponse: routeResponse,
            from: from,
            isAffiliate: isAffiliate
        )
    }

    private func buildTransactionWithFallback(
        chain: String,
        routeResponse: KyberSwapRouteResponse,
        from: String,
        isAffiliate: Bool
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {

        // First attempt with gas estimation enabled
        do {
            return try await buildTransaction(
                chain: chain,
                routeResponse: routeResponse,
                from: from,
                enableGasEstimation: true,
                isAffiliate: isAffiliate
            )
        } catch KyberSwapError.transactionWillRevert(let message) where message.contains("TransferHelper") {
            // TransferHelper error likely due to insufficient allowance during gas estimation
            // Retry without gas estimation
            return try await buildTransaction(
                chain: chain,
                routeResponse: routeResponse,
                from: from,
                enableGasEstimation: false,
                isAffiliate: isAffiliate
            )
        }
    }

    private func buildTransaction(
        chain: String,
        routeResponse: KyberSwapRouteResponse,
        from: String,
        enableGasEstimation: Bool,
        isAffiliate: Bool
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {

        let buildUrl = Endpoint.buildKyberSwapTransaction(chain: chain)

        let buildPayload = KyberSwapBuildRequest(
            routeSummary: routeResponse.data.routeSummary,
            sender: from,
            recipient: from,
            slippageTolerance: 100,
            deadline: Int(Date().timeIntervalSince1970) + 1200,
            enableGasEstimation: enableGasEstimation,
            source: KyberSwapService.sourceIdentifier,
            referral: isAffiliate ? KyberSwapService.referrerAddress : nil,
            ignoreCappedSlippage: false
        )

        var buildRequest = URLRequest(url: buildUrl)
        buildRequest.httpMethod = "POST"
        buildRequest.allHTTPHeaderFields = [
            "accept": "application/json",
            "content-type": "application/json",
            "x-client-id": KyberSwapService.sourceIdentifier
        ]
        buildRequest.httpBody = try JSONEncoder().encode(buildPayload)

        let (buildData, _) = try await URLSession.shared.data(for: buildRequest)

        // First check if it's an error response by looking for non-zero code
        do {
            let errorResponse = try JSONDecoder().decode(KyberSwapErrorResponse.self, from: buildData)
            if errorResponse.code != 0 {
                // Enhanced error handling for gas estimation failures
                if errorResponse.message.contains("execution reverted") {
                    throw KyberSwapError.transactionWillRevert(message: errorResponse.message)
                } else if errorResponse.message.contains("insufficient allowance") {
                    throw KyberSwapError.insufficientAllowance(message: errorResponse.message)
                } else if errorResponse.message.contains("insufficient funds") {
                    throw KyberSwapError.insufficientFunds(message: errorResponse.message)
                } else {
                    throw KyberSwapError.apiError(code: errorResponse.code, message: errorResponse.message, details: errorResponse.details)
                }
            }
            // If we get here, it's a success response with code 0, continue to decode
        } catch let error as KyberSwapError {
            // Re-throw our parsed errors
            throw error
        } catch _ {
            // If we can't decode as error response, continue to try as success response
        }

        // If we get here, try to decode as success response
        var buildResponse = try JSONDecoder().decode(KyberSwapQuote.self, from: buildData)

        let gasPrice = routeResponse.data.routeSummary.gasPrice

        // Update gasPrice from route response
        buildResponse.data.gasPrice = gasPrice

        guard let chainEnum = Chain.allCases.first(where: { (try? getChainName(for: $0)) == chain }) else {
            throw KyberSwapError.apiError(code: -1, message: "Unknown chain: \(chain)", details: nil)
        }
        let calculatedGas = buildResponse.gasForChain(chainEnum)

        let finalGas: BigInt
        if calculatedGas == 0 {
            finalGas = BigInt(EVMHelper.defaultETHSwapGasUnit)
        } else {
            finalGas = BigInt(calculatedGas)
        }
        buildResponse.data.gas = finalGas.description
        let gasPriceValue = BigInt(gasPrice) ?? BigInt("20000000000")
        let minGasPrice = BigInt("1000000000")
        let finalGasPrice = gasPriceValue < minGasPrice ? minGasPrice : gasPriceValue

        let fee = finalGas * finalGasPrice

        let evmQuote = EVMQuote(
            dstAmount: buildResponse.dstAmount,
            tx: EVMQuote.Transaction(
                from: buildResponse.tx.from,
                to: buildResponse.tx.to,
                data: buildResponse.data.data,
                value: buildResponse.tx.value,
                gasPrice: buildResponse.tx.gasPrice,
                gas: buildResponse.tx.gas,
                swapFee: "0",
                swapFeeTokenContract: ""
            )
        )

        return (evmQuote, fee)
    }

    func getChainName(for chain: Chain) throws -> String {
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
            throw KyberSwapError.apiError(code: -1, message: "Unsupported chain for KyberSwap: \(chain)", details: nil)
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
            let tokenInMarketPriceAvailable: Bool?
            let tokenOut: String
            let amountOut: String
            let amountOutUsd: String
            let tokenOutMarketPriceAvailable: Bool?
            let gas: String
            let gasPrice: String
            let gasUsd: String
            let l1FeeUsd: String?
            let additionalCostUsd: String?
            let additionalCostMessage: String?
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

            // Handle nil/null first
            if value is NSNull {
                try container.encodeNil()
                return
            }

            // Handle primitive types
            if let intVal = value as? Int {
                try container.encode(intVal)
            } else if let doubleVal = value as? Double {
                try container.encode(doubleVal)
            } else if let floatVal = value as? Float {
                try container.encode(floatVal)
            } else if let stringVal = value as? String {
                try container.encode(stringVal)
            } else if let boolVal = value as? Bool {
                try container.encode(boolVal)
            }
            // Handle arrays - check for AnyCodable arrays first
            else if let arrayVal = value as? [AnyCodable] {
                try container.encode(arrayVal)
            } else if let arrayVal = value as? [Any] {
                let encodableArray = arrayVal.map(AnyCodable.init)
                try container.encode(encodableArray)
            } else if let arrayVal = value as? [String] {
                try container.encode(arrayVal)
            } else if let arrayVal = value as? [Int] {
                try container.encode(arrayVal)
            } else if let arrayVal = value as? [Double] {
                try container.encode(arrayVal)
            } else if let arrayVal = value as? [Bool] {
                try container.encode(arrayVal)
            }
            // Handle dictionaries - check for AnyCodable dictionaries first (CRITICAL FIX)
            else if let dictVal = value as? [String: AnyCodable] {
                try container.encode(dictVal)
            } else if let dictVal = value as? [String: Any] {
                let encodableDict = dictVal.mapValues(AnyCodable.init)
                try container.encode(encodableDict)
            } else if let dictVal = value as? [String: String] {
                try container.encode(dictVal)
            } else if let dictVal = value as? [String: Int] {
                try container.encode(dictVal)
            } else if let dictVal = value as? [String: Double] {
                try container.encode(dictVal)
            } else if let dictVal = value as? [String: Bool] {
                try container.encode(dictVal)
            }
            // Handle NSNumber (which can contain Int, Double, Bool)
            else if let numberVal = value as? NSNumber {
                // Check if it's actually a boolean
                if CFBooleanGetTypeID() == CFGetTypeID(numberVal) {
                    try container.encode(numberVal.boolValue)
                } else if CFNumberIsFloatType(numberVal) {
                    try container.encode(numberVal.doubleValue)
                } else {
                    try container.encode(numberVal.intValue)
                }
            }
            // Fallback
            else {
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
        let enableGasEstimation: Bool
        let source: String?
        let referral: String?
        let ignoreCappedSlippage: Bool?

        init(routeSummary: KyberSwapRouteResponse.RouteSummary, sender: String, recipient: String, slippageTolerance: Int = 100, deadline: Int? = nil, enableGasEstimation: Bool = true, source: String? = KyberSwapService.sourceIdentifier, referral: String? = nil, ignoreCappedSlippage: Bool? = false) {
            self.routeSummary = routeSummary
            self.sender = sender
            self.recipient = recipient
            self.slippageTolerance = slippageTolerance
            self.deadline = deadline ?? Int(Date().timeIntervalSince1970) + 1200
            self.enableGasEstimation = enableGasEstimation
            self.source = source
            self.referral = referral
            self.ignoreCappedSlippage = ignoreCappedSlippage
        }
    }

    struct KyberSwapErrorResponse: Codable {
        let code: Int
        let message: String
        let details: [String]?
        let requestId: String?
    }
}

enum KyberSwapError: Error, LocalizedError {
    case apiError(code: Int, message: String, details: [String]?)
    case transactionWillRevert(message: String)
    case insufficientAllowance(message: String)
    case insufficientFunds(message: String)

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let message, let details):
            let detailsStr = details?.isEmpty == false ? " - \(details!.joined(separator: ", "))" : ""
            return "KyberSwap API Error \(code): \(message)\(detailsStr)"
        case .transactionWillRevert(let message):
            return "Transaction will revert: \(message)"
        case .insufficientAllowance(let message):
            return "Insufficient allowance: \(message)"
        case .insufficientFunds(let message):
            return "Insufficient funds: \(message)"
        }
    }
}
