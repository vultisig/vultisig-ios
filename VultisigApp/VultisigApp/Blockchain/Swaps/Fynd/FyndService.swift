//
//  FyndService.swift
//  VultisigApp
//
//  Same-chain EVM swaps through Propeller Heads' Fynd aggregator. Every swap
//  settles through the chain's TychoRouterV3, pinned in `EVMSwapTxGuard`.
//

import BigInt
import Foundation

enum FyndError: Error, LocalizedError, Equatable {
    case notEnabled
    case unsupportedChain
    case noRoute
    case timeout
    case rateLimited
    case quoteFailed(status: String)
    case apiError(code: String, message: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Fynd is not enabled"
        case .unsupportedChain:
            return "Fynd does not support this chain"
        case .noRoute:
            return "Fynd found no route for this pair"
        case .timeout:
            return "Fynd quote timed out"
        case .rateLimited:
            return "Fynd rate limit exceeded"
        case .quoteFailed(let status):
            return "Fynd quote failed: \(status)"
        case .apiError(let code, let message):
            return "Fynd error \(code): \(message)"
        case .invalidResponse(let reason):
            return "Fynd returned an invalid quote: \(reason)"
        }
    }
}

struct FyndService {
    static let shared = FyndService()

    struct Endpoint: Equatable {
        let baseURL: URL
        /// Set only for the debug direct-key path.
        let apiKey: String?
        /// Whether quotes can carry the Vultisig client fee. Only the proxy
        /// holds the fee-receiver key that must sign each quote.
        let signsClientFee: Bool
    }

    /// Vultisig proxy in front of `fynd-api.propellerheads.xyz`. It injects the
    /// API key and signs the client fee. The route does not exist yet.
    static let proxyBaseURL = URL(string: "https://api.vultisig.com/fynd")!
    static let directBaseURL = URL(string: "https://fynd-api.propellerheads.xyz")!

    /// Same base fee as KyberSwap/1inch, before the VULT tier discount.
    static let baseAffiliateFeeBps = 50
    /// TODO-confirm: the address of the proxy's fee-signer key, the only key that
    /// can sign Fynd's `ClientFee` message for it. Fees accrue to its vault
    /// inside the router and must be swept to the treasury. Unset until infra
    /// creates it; while unset, Fynd is never quoted through the proxy.
    static let feeReceiver: String? = nil
    /// Fynd keeps 20% of the client fee: Vultisig receives `bps × 8000 / 10000`.
    static let integratorShareBps = 8000
    static let clientFeeSignatureBytes = 65
    static let defaultSlippageBps = 100
    static let quoteTimeoutMs = 5000
    /// `gas_estimate` covers the route's swaps only, not the router's transfer,
    /// fee and signature checks. Unused gas is refunded, so pad generously; the
    /// signer still floors the limit at the fee oracle's estimate.
    static let routerGasOverhead: Int64 = 150_000

    static let enabledDefaultsKey = "fyndSwapEnabled"
    /// Last value of the remote `fynd-swap` flag, refreshed in the background.
    static let remoteFlagDefaultsKey = "fyndSwapRemoteFlag"

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Fynd is quoted when the remote `fynd-swap` flag is on (default off) or a
    /// debug build forces it, and only where it can charge correctly: the debug
    /// direct-key path (zero fee) or the proxy with a configured fee receiver.
    /// Matches Android's `FyndFeatureGate`.
    static var isEnabled: Bool {
        let flagged = isDebugForced || UserDefaults.standard.bool(forKey: remoteFlagDefaultsKey)
        return flagged && (endpoint.apiKey != nil || feeReceiver != nil)
    }

    private static var isDebugForced: Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "forcedSwapProvider") == "fynd"
            || defaults.bool(forKey: enabledDefaultsKey)
            || ProcessInfo.processInfo.environment["FYND_ENABLED"] == "1"
        #else
        return false
        #endif
    }

    /// Caches the remote flag so the synchronous provider list can read it.
    /// A failed fetch reads as off, so the flag fails closed.
    static func refreshRemoteFlag(service: FeatureFlagService = FeatureFlagService()) async {
        let enabled = await service.isFeatureEnabled(feature: .fyndSwap)
        UserDefaults.standard.set(enabled, forKey: remoteFlagDefaultsKey)
    }

    static var endpoint: Endpoint {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let override = env["FYND_BASE_URL"].flatMap { $0.isEmpty ? nil : URL(string: $0) }
        if let apiKey = env["FYND_API_KEY"], !apiKey.isEmpty {
            return Endpoint(baseURL: override ?? directBaseURL, apiKey: apiKey, signsClientFee: false)
        }
        if let override {
            return Endpoint(baseURL: override, apiKey: nil, signsClientFee: true)
        }
        #endif
        return Endpoint(baseURL: proxyBaseURL, apiKey: nil, signsClientFee: true)
    }

    static func chainName(for chain: Chain) -> String? {
        switch chain {
        case .ethereum: return "ethereum"
        case .base: return "base"
        case .arbitrum: return "arbitrum"
        default: return nil
        }
    }

    /// Vultisig's net fee: the KyberSwap shape, `50 − VULT discount`, floored at 0.
    /// Referral codes do not apply to same-chain aggregator routes.
    static func affiliateBps(vultTierDiscount: Int) -> Int {
        max(0, baseAffiliateFeeBps - vultTierDiscount)
    }

    /// The bps to request so Vultisig nets `affiliateBps` after Fynd's 20%:
    /// `ceil(affiliateBps / 0.8)`.
    static func clientFeeBps(affiliateBps: Int) -> Int {
        guard affiliateBps > 0 else { return 0 }
        return (affiliateBps * 10_000 + integratorShareBps - 1) / integratorShareBps
    }

    /// Vultisig's share of a client fee of `clientFeeBps` on `amountOut`, using
    /// the router's integer arithmetic (Fynd docs, "Fee breakdown").
    static func expectedClientFee(amountOut: BigInt, clientFeeBps: Int) -> BigInt {
        let gross = amountOut * BigInt(clientFeeBps) / 10_000
        let routerShare = amountOut * BigInt(clientFeeBps) * 2_000 / 100_000_000
        return gross - routerShare
    }

    static func slippageString(bps: Int) -> String {
        (Decimal(bps) / 10_000).description
    }

    static func tokenAddress(_ coin: Coin) -> String {
        coin.isNativeToken ? nativeTokenAddress : coin.contractAddress
    }

    func fetchQuote(
        fromCoin: Coin,
        toCoin: Coin,
        amount: BigInt,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {
        guard Self.isEnabled else { throw FyndError.notEnabled }
        guard fromCoin.chain == toCoin.chain,
              let chainName = Self.chainName(for: fromCoin.chain),
              let router = EVMSwapTxGuard.fyndRouter(for: fromCoin.chain) else {
            throw FyndError.unsupportedChain
        }

        let endpoint = Self.endpoint
        let affiliateBps = endpoint.signsClientFee ? Self.affiliateBps(vultTierDiscount: vultTierDiscount) : 0
        let clientFeeBps = Self.clientFeeBps(affiliateBps: affiliateBps)
        let feeReceiver = Self.feeReceiver ?? ""
        // Never drop a fee the vault owes to zero because no receiver is set.
        guard clientFeeBps == 0 || !feeReceiver.isEmpty else { throw FyndError.notEnabled }
        let slippage = slippageBps ?? Self.defaultSlippageBps

        let request = FyndQuoteRequest(
            orders: [
                .init(
                    tokenIn: Self.tokenAddress(fromCoin),
                    tokenOut: Self.tokenAddress(toCoin),
                    amount: String(amount),
                    side: "sell",
                    sender: fromCoin.address,
                    receiver: fromCoin.address
                )
            ],
            options: .init(
                timeoutMs: Self.quoteTimeoutMs,
                minResponses: 1,
                encodingOptions: .init(
                    slippage: Self.slippageString(bps: slippage),
                    transferType: "transfer_from",
                    clientFeeParams: clientFeeBps > 0
                        ? .init(bps: clientFeeBps, receiver: feeReceiver)
                        : nil
                )
            )
        )

        let order = try await requestQuote(chain: chainName, body: request, endpoint: endpoint)
        let context = FyndQuoteContext(
            router: router,
            recipient: fromCoin.address,
            tokenIn: Self.tokenAddress(fromCoin),
            tokenOut: Self.tokenAddress(toCoin),
            sellAmount: amount,
            slippageBps: slippage,
            clientFeeBps: clientFeeBps,
            feeReceiver: feeReceiver,
            now: Date()
        )
        let validated = try Self.validate(order, context: context)
        return Self.makeQuote(validated, sender: fromCoin.address, tokenOut: Self.tokenAddress(toCoin))
    }

    private func requestQuote(chain: String, body: FyndQuoteRequest, endpoint: Endpoint) async throws -> FyndOrderQuote {
        let data: Data
        do {
            data = try await httpClient.request(FyndAPI.quote(chain: chain, body: body, endpoint: endpoint)).data
        } catch HTTPError.statusCode(let code, let body) {
            throw Self.mapHTTPError(statusCode: code, body: body)
        } catch HTTPError.timeout {
            throw FyndError.timeout
        }
        guard let order = try JSONDecoder().decode(FyndQuoteResponse.self, from: data).orders.first else {
            throw FyndError.invalidResponse("no order in response")
        }
        return order
    }

    static func mapHTTPError(statusCode: Int, body: Data?) -> Error {
        if statusCode == 429 { return FyndError.rateLimited }
        // Keep 5xx as an HTTP status so the shared transient-retry path sees it.
        if statusCode < 500, let body, let error = try? JSONDecoder().decode(FyndErrorResponse.self, from: body) {
            return FyndError.apiError(code: error.code, message: error.error)
        }
        return HTTPError.statusCode(statusCode, body)
    }
}

// MARK: - Quote validation

struct FyndQuoteContext {
    let router: String
    /// The vault address that submits the swap and receives its output.
    let recipient: String
    /// Request token addresses; the zero address is the native coin.
    let tokenIn: String
    let tokenOut: String
    let sellAmount: BigInt
    let slippageBps: Int
    /// Gross client fee requested; 0 when the quote carries no client fee.
    let clientFeeBps: Int
    let feeReceiver: String
    let now: Date

    var sellsNative: Bool { FyndService.isNative(tokenIn) }
}

struct FyndValidatedQuote: Equatable {
    let to: String
    let value: String
    let data: String
    /// What the user is quoted to receive: `amount_out − router_fee − client_fee`.
    let netAmountOut: BigInt
    /// Vultisig's share of the client fee, in output-token units.
    let clientFee: BigInt
    let gasEstimate: Int64
    let gasPrice: String
}

extension FyndService {
    static let nativeTokenAddress = "0x0000000000000000000000000000000000000000"
    /// TychoRouterV3's `ETH_ADDRESS`, which the encoder may use for the native side.
    static let routerNativeAddress = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    static let feeUnitsPerBps = 10_000
    /// Fynd's own fee defaults to 0 bps; allow a small negotiated rate on top
    /// of its 20% of the client fee. Same cap as Android.
    static let maxRouterFeeBps = 10

    /// The most `router_fee` a quote may report: Fynd's share of the client fee
    /// plus `maxRouterFeeBps` of the output. An unbounded router fee would let a
    /// quote hide a near-zero minimum behind fees.
    static func maxRouterFee(amountOut: BigInt, clientFeeBps: Int) -> BigInt {
        let routerShareOfClientFee = amountOut * BigInt(clientFeeBps) / 10_000
            - expectedClientFee(amountOut: amountOut, clientFeeBps: clientFeeBps)
        return routerShareOfClientFee + amountOut * BigInt(maxRouterFeeBps) / 10_000
    }

    /// A fee signature must outlive multi-device keysign; one expiring sooner
    /// would revert on-chain.
    static let minFeeDeadlineSeconds: TimeInterval = 15 * 60

    static func isNative(_ token: String) -> Bool {
        token.lowercased() == nativeTokenAddress
    }

    /// The API names the native coin with the zero address, but TychoRouterV3
    /// takes `ETH_ADDRESS` (0xEeee…) as the outer token and reverts on zero.
    static func calldataToken(matches requestToken: String, _ calldataToken: String) -> Bool {
        let expected = isNative(requestToken) ? routerNativeAddress : requestToken.lowercased()
        return calldataToken.lowercased() == expected
    }

    /// Rejects any quote whose calldata does not perform exactly the swap that
    /// was asked for. The router call is decoded rather than trusted from the
    /// response metadata, because the app (not a trusted backend) signs it.
    static func validate(_ order: FyndOrderQuote, context: FyndQuoteContext) throws -> FyndValidatedQuote {
        switch order.status {
        case "success":
            break
        case "no_route_found", "insufficient_liquidity":
            throw FyndError.noRoute
        case "timeout":
            throw FyndError.timeout
        default:
            throw FyndError.quoteFailed(status: order.status)
        }

        guard let tx = order.transaction, let fees = order.feeBreakdown else {
            throw FyndError.invalidResponse("missing transaction or fee breakdown")
        }
        guard let amountOut = BigInt(order.amountOut ?? ""),
              let routerFee = BigInt(fees.routerFee),
              let clientFee = BigInt(fees.clientFee),
              let minReceived = BigInt(fees.minAmountReceived),
              let value = BigInt(tx.value),
              amountOut > 0, routerFee >= 0, clientFee >= 0, value >= 0 else {
            throw FyndError.invalidResponse("unparseable amounts")
        }
        let calldata = tx.data.lowercased().stripHexPrefix()
        guard calldata.count % 2 == 0, calldata.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw FyndError.invalidResponse("calldata is not hex")
        }
        guard tx.to.lowercased() == context.router.lowercased() else {
            throw FyndError.invalidResponse("router \(tx.to) is not the pinned router \(context.router)")
        }
        guard let call = FyndRouterCall.decode(calldata) else {
            throw FyndError.invalidResponse("calldata is not a TychoRouterV3 swap")
        }
        guard call.amountIn == context.sellAmount, BigInt(order.amountIn ?? "") == context.sellAmount else {
            throw FyndError.invalidResponse("sell amount differs from \(context.sellAmount)")
        }
        guard calldataToken(matches: context.tokenIn, call.tokenIn),
              calldataToken(matches: context.tokenOut, call.tokenOut) else {
            throw FyndError.invalidResponse("calldata swaps \(call.tokenIn) for \(call.tokenOut)")
        }
        guard call.receiver.lowercased() == context.recipient.lowercased() else {
            throw FyndError.invalidResponse("calldata pays \(call.receiver), not the vault")
        }
        guard value == (context.sellsNative ? context.sellAmount : 0) else {
            throw FyndError.invalidResponse("tx value \(value) does not match the sell")
        }

        let routerFeeCap = maxRouterFee(amountOut: amountOut, clientFeeBps: context.clientFeeBps)
        guard routerFee <= routerFeeCap else {
            throw FyndError.invalidResponse("router fee \(routerFee) is above \(routerFeeCap)")
        }

        let netAmountOut = amountOut - routerFee - clientFee
        let outputFloor = netAmountOut * BigInt(10_000 - context.slippageBps) / 10_000
        // One unit of slack for the floor's rounding, as on Android.
        guard netAmountOut > 0, minReceived > 0, minReceived >= outputFloor - 1, minReceived <= netAmountOut,
              call.minAmountOut == minReceived, call.expectedAmountOut == amountOut else {
            throw FyndError.invalidResponse("output floor does not match the requested slippage")
        }

        if let reported = tx.clientFeeSignatureOffset, reported != call.clientSignatureOffset {
            throw FyndError.invalidResponse("signature offset \(reported) disagrees with the calldata")
        }
        try validateClientFee(call: call, clientFee: clientFee, amountOut: amountOut, deadline: order.clientFeeDeadline, context: context)

        let gasEstimate = Int64(order.gasEstimate ?? "") ?? 0
        guard (0...maxGasEstimate).contains(gasEstimate) else {
            throw FyndError.invalidResponse("gas estimate \(gasEstimate) is out of range")
        }
        return FyndValidatedQuote(
            to: tx.to,
            value: String(value),
            data: "0x" + calldata,
            netAmountOut: netAmountOut,
            clientFee: clientFee,
            gasEstimate: gasEstimate,
            gasPrice: order.gasPrice ?? ""
        )
    }

    private static func validateClientFee(
        call: FyndRouterCall,
        clientFee: BigInt,
        amountOut: BigInt,
        deadline: Int?,
        context: FyndQuoteContext
    ) throws {
        guard context.clientFeeBps > 0 else {
            guard clientFee == 0, call.clientFeeUnits == 0 else {
                throw FyndError.invalidResponse("unexpected client fee \(clientFee)")
            }
            return
        }

        guard call.clientFeeUnits == BigInt(context.clientFeeBps * feeUnitsPerBps) else {
            throw FyndError.invalidResponse("calldata charges \(call.clientFeeUnits) fee units, not \(context.clientFeeBps) bps")
        }
        let expected = expectedClientFee(amountOut: amountOut, clientFeeBps: context.clientFeeBps)
        // Fynd mirrors the router's integer arithmetic, so the share is exact.
        guard clientFee == expected else {
            throw FyndError.invalidResponse("client fee \(clientFee) does not match \(context.clientFeeBps) bps (expected \(expected))")
        }
        guard call.clientFeeReceiver.lowercased() == context.feeReceiver.lowercased() else {
            throw FyndError.invalidResponse("client fee goes to \(call.clientFeeReceiver), not the Vultisig receiver")
        }
        guard call.maxClientContribution == 0 else {
            throw FyndError.invalidResponse("client fee subsidizes slippage")
        }
        guard call.clientSignature.count == clientFeeSignatureBytes * 2,
              call.clientSignature.contains(where: { $0 != "0" }) else {
            throw FyndError.invalidResponse("client fee signature is missing or the unsigned placeholder")
        }
        guard let deadline, BigInt(deadline) == call.clientFeeDeadline,
              TimeInterval(deadline) >= context.now.timeIntervalSince1970 + minFeeDeadlineSeconds else {
            throw FyndError.invalidResponse("client fee deadline missing, mismatched or too soon")
        }
    }

    /// Fynd routes are a few hundred thousand gas; anything far above that is
    /// not a quote we would sign.
    static let maxGasEstimate: Int64 = 10_000_000

    static func makeQuote(_ quote: FyndValidatedQuote, sender: String, tokenOut: String) -> (quote: EVMQuote, fee: BigInt?) {
        let gas = quote.gasEstimate > 0 ? quote.gasEstimate * 3 / 2 + routerGasOverhead : 0
        let gasPrice = KyberSwapQuote.parseGasPriceWei(quote.gasPrice.nilIfEmpty)
        let evmQuote = EVMQuote(
            dstAmount: String(quote.netAmountOut),
            tx: EVMQuote.Transaction(
                from: sender,
                to: quote.to,
                data: quote.data,
                value: quote.value,
                gasPrice: quote.gasPrice,
                gas: gas,
                swapFee: quote.clientFee > 0 ? String(quote.clientFee) : nil,
                swapFeeTokenContract: quote.clientFee > 0 ? tokenOut : ""
            )
        )
        let networkFee = gas > 0 ? BigInt(gas) * gasPrice : nil
        return (evmQuote, networkFee)
    }
}
