//
//  KyberSwapService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import BigInt
import Foundation

struct KyberSwapService {
    static let shared = KyberSwapService()

    static let sourceIdentifier = "vultisig-ios"
    static let referrerAddress = "0x8E247a480449c84a5fDD25974A8501f3EFa4ABb9"

    private let httpClient: HTTPClientProtocol = HTTPClient()

    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }

    func fetchQuotes(chain: String, source: String, destination: String, amount: String, from: String, affiliateBps: Int) async throws -> (quote: EVMQuote, fee: BigInt?) {
        let sourceAddress = source.isEmpty ? nullAddress : source
        let destinationAddress = destination.isEmpty ? nullAddress : destination

        let params = KyberSwapAPI.RouteParams(
            tokenIn: sourceAddress,
            tokenOut: destinationAddress,
            amountIn: amount,
            saveGas: false,
            gasInclude: true,
            slippageTolerance: 100,
            affiliateBps: affiliateBps,
            sourceIdentifier: affiliateBps > 0 ? KyberSwapService.sourceIdentifier : nil,
            referrerAddress: affiliateBps > 0 ? KyberSwapService.referrerAddress : nil
        )

        let routeResponse: KyberSwapRouteResponse = try await fetchAndDecodeKyber(
            KyberSwapAPI.routes(chain: chain, params: params)
        )

        // Try with gas estimation first, retry without if TransferHelper error occurs
        return try await buildTransactionWithFallback(
            chain: chain,
            routeResponse: routeResponse,
            from: from,
            affiliateBps: affiliateBps
        )
    }

    /// Performs a request and routes the body through `decodeKyberResponse`.
    /// `KyberSwapAPI` only whitelists 200/400, so 5xx responses arrive as
    /// `HTTPError.statusCode(_, data?)`; we still want to map their typed
    /// error envelope to `KyberSwapError` instead of leaking a generic HTTP error.
    private func fetchAndDecodeKyber<T: Decodable>(_ target: TargetType) async throws -> T {
        do {
            let response = try await httpClient.request(target)
            return try decodeKyberResponse(response.data)
        } catch HTTPError.statusCode(let statusCode, let data?) {
            // Try to map the body to a typed KyberSwapError. If decoding the
            // error envelope itself fails (e.g. 5xx returns HTML), surface the
            // original HTTP status instead of a misleading DecodingError.
            do {
                return try decodeKyberResponse(data)
            } catch let kyberError as KyberSwapError {
                throw kyberError
            } catch {
                throw HTTPError.statusCode(statusCode, data)
            }
        }
    }

    /// KyberSwap returns either a success envelope (`code == 0`) or an error
    /// envelope that shares the same top-level keys. HTTP 400 is reserved for
    /// validation/execution errors with structured messages. This decodes the
    /// error envelope first and maps known messages to typed
    /// `KyberSwapError` cases before falling back to the success model.
    private func decodeKyberResponse<T: Decodable>(_ data: Data) throws -> T {
        if let error = try? JSONDecoder().decode(KyberSwapErrorResponse.self, from: data),
           error.code != 0 {
            if error.message.contains("execution reverted") {
                throw KyberSwapError.transactionWillRevert(message: error.message)
            }
            if error.message.contains("insufficient allowance") {
                throw KyberSwapError.insufficientAllowance(message: error.message)
            }
            if error.message.contains("insufficient funds") {
                throw KyberSwapError.insufficientFunds(message: error.message)
            }
            throw KyberSwapError.apiError(code: error.code, message: error.message, details: error.details)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func buildTransactionWithFallback(
        chain: String,
        routeResponse: KyberSwapRouteResponse,
        from: String,
        affiliateBps: Int
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {
        // First attempt with gas estimation enabled
        do {
            return try await buildTransaction(
                chain: chain,
                routeResponse: routeResponse,
                from: from,
                enableGasEstimation: true,
                affiliateBps: affiliateBps
            )
        } catch let KyberSwapError.transactionWillRevert(message) where message.contains("TransferHelper") {
            // TransferHelper error likely due to insufficient allowance during gas estimation
            // Retry without gas estimation
            return try await buildTransaction(
                chain: chain,
                routeResponse: routeResponse,
                from: from,
                enableGasEstimation: false,
                affiliateBps: affiliateBps
            )
        }
    }

    private func buildTransaction(
        chain: String,
        routeResponse: KyberSwapRouteResponse,
        from: String,
        enableGasEstimation: Bool,
        affiliateBps: Int
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {
        let buildPayload = KyberSwapBuildRequest(
            routeSummary: routeResponse.data.routeSummary,
            sender: from,
            recipient: from,
            slippageTolerance: 100,
            deadline: Int(Date().timeIntervalSince1970) + 1200,
            enableGasEstimation: enableGasEstimation,
            source: KyberSwapService.sourceIdentifier,
            referral: affiliateBps > 0 ? KyberSwapService.referrerAddress : nil,
            ignoreCappedSlippage: false,
            feeAmount: affiliateBps > 0 ? affiliateBps : nil,
            chargeFeeBy: affiliateBps > 0 ? "currency_out" : nil,
            isInBps: affiliateBps > 0 ? true : nil,
            feeReceiver: affiliateBps > 0 ? KyberSwapService.referrerAddress : nil
        )

        var buildResponse: KyberSwapQuote = try await fetchAndDecodeKyber(
            KyberSwapAPI.buildTransaction(chain: chain, body: buildPayload)
        )

        let gasPrice = routeResponse.data.routeSummary.gasPrice

        // Update gasPrice from route response
        buildResponse.data.gasPrice = gasPrice

        let kyberGas = buildResponse.gas
        let finalGas: BigInt
        if kyberGas == 0 {
            finalGas = BigInt(EVMHelper.defaultETHSwapGasUnit)
        } else {
            finalGas = BigInt(kyberGas)
        }
        buildResponse.data.gas = finalGas.description
        // KyberSwap's routeSummary.gasPrice is the network's effective gas
        // price as the aggregator sees it; use it verbatim. The fallback
        // (1 gwei) only fires when the API returns an unparseable value.
        let finalGasPrice = KyberSwapQuote.parseGasPriceWei(gasPrice)

        let fee = finalGas * finalGasPrice

        let dstAmountBigInt = BigInt(buildResponse.dstAmount) ?? BigInt(0)
        let affiliateFeeAmount = affiliateBps > 0 ? dstAmountBigInt * BigInt(affiliateBps) / BigInt(10000) : BigInt(0)

        let evmQuote = EVMQuote(
            dstAmount: buildResponse.dstAmount,
            tx: EVMQuote.Transaction(
                from: buildResponse.tx.from,
                to: buildResponse.tx.to,
                data: buildResponse.data.data,
                value: buildResponse.tx.value,
                gasPrice: buildResponse.tx.gasPrice,
                gas: buildResponse.tx.gas,
                swapFee: affiliateFeeAmount.description,
                swapFeeTokenContract: routeResponse.data.routeSummary.tokenOut
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

extension KyberSwapService {
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
        let feeAmount: Int?
        let chargeFeeBy: String?
        let isInBps: Bool?
        let feeReceiver: String?

        init(routeSummary: KyberSwapRouteResponse.RouteSummary, sender: String, recipient: String, slippageTolerance: Int = 100, deadline: Int? = nil, enableGasEstimation: Bool = true, source: String? = KyberSwapService.sourceIdentifier, referral: String? = nil, ignoreCappedSlippage: Bool? = false, feeAmount: Int? = nil, chargeFeeBy: String? = nil, isInBps: Bool? = nil, feeReceiver: String? = nil) {
            self.routeSummary = routeSummary
            self.sender = sender
            self.recipient = recipient
            self.slippageTolerance = slippageTolerance
            self.deadline = deadline ?? Int(Date().timeIntervalSince1970) + 1200
            self.enableGasEstimation = enableGasEstimation
            self.source = source
            self.referral = referral
            self.ignoreCappedSlippage = ignoreCappedSlippage
            self.feeAmount = feeAmount
            self.chargeFeeBy = chargeFeeBy
            self.isInBps = isInBps
            self.feeReceiver = feeReceiver
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
        case let .apiError(code, message, details):
            let detailsStr = details?.isEmpty == false ? " - \(details!.joined(separator: ", "))" : ""
            return "KyberSwap API Error \(code): \(message)\(detailsStr)"
        case let .transactionWillRevert(message):
            return "Transaction will revert: \(message)"
        case let .insufficientAllowance(message):
            return "Insufficient allowance: \(message)"
        case let .insufficientFunds(message):
            return "Insufficient funds: \(message)"
        }
    }
}
