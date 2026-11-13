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
    /// TODO-confirm: must be the address of the proxy's fee-signer key, which is
    /// the only key that can sign Fynd's `ClientFee` message for it. Defaults to
    /// the treasury every other EVM aggregator pays. Fees accrue to this
    /// address's vault inside the router and must be swept.
    static let feeReceiver = KyberSwapService.referrerAddress
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

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Off in release builds until the proxy route and its fee signer are live.
    /// Debug builds turn it on with Settings → Advanced → force "Fynd", the
    /// `fyndSwapEnabled` default, or `FYND_ENABLED=1`.
    static var isEnabled: Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "forcedSwapProvider") == "fynd" { return true }
        if defaults.bool(forKey: enabledDefaultsKey) { return true }
        if ProcessInfo.processInfo.environment["FYND_ENABLED"] == "1" { return true }
        #endif
        return false
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
        coin.isNativeToken ? "0x0000000000000000000000000000000000000000" : coin.contractAddress
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
                        ? .init(bps: clientFeeBps, receiver: Self.feeReceiver)
                        : nil
                )
            )
        )

        let order = try await requestQuote(chain: chainName, body: request, endpoint: endpoint)
        let context = FyndQuoteContext(
            router: router,
            recipient: fromCoin.address,
            sellAmount: amount,
            sellsNative: fromCoin.isNativeToken,
            slippageBps: slippage,
            clientFeeBps: clientFeeBps,
            feeReceiver: Self.feeReceiver,
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
        if let body, let error = try? JSONDecoder().decode(FyndErrorResponse.self, from: body) {
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
    let sellAmount: BigInt
    let sellsNative: Bool
    let slippageBps: Int
    /// Gross client fee requested; 0 when the quote carries no client fee.
    let clientFeeBps: Int
    let feeReceiver: String
    let now: Date
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
    /// Rejects any quote whose signed fields differ from what was asked for.
    /// Mirrors shapeshift/web's `validateFyndQuoteResponse`, plus a receiver
    /// check, since the app (not a trusted backend) builds the transaction.
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
        guard let amountIn = BigInt(order.amountIn ?? ""),
              let amountOut = BigInt(order.amountOut ?? ""),
              let routerFee = BigInt(fees.routerFee),
              let clientFee = BigInt(fees.clientFee),
              let minReceived = BigInt(fees.minAmountReceived),
              let value = BigInt(tx.value),
              amountOut > 0, routerFee >= 0, clientFee >= 0, value >= 0 else {
            throw FyndError.invalidResponse("unparseable amounts")
        }
        let calldata = tx.data.lowercased().stripHexPrefix()
        guard !calldata.isEmpty, calldata.count % 2 == 0,
              calldata.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw FyndError.invalidResponse("calldata is not hex")
        }

        guard tx.to.lowercased() == context.router.lowercased() else {
            throw FyndError.invalidResponse("router \(tx.to) is not the pinned router \(context.router)")
        }
        guard amountIn == context.sellAmount else {
            throw FyndError.invalidResponse("quoted sell amount \(amountIn) differs from \(context.sellAmount)")
        }
        guard value == (context.sellsNative ? context.sellAmount : 0) else {
            throw FyndError.invalidResponse("tx value \(value) does not match the sell")
        }

        let netAmountOut = amountOut - routerFee - clientFee
        let outputFloor = netAmountOut * BigInt(10_000 - context.slippageBps) / 10_000
        guard netAmountOut > 0, minReceived > 0, minReceived >= outputFloor, minReceived <= netAmountOut else {
            throw FyndError.invalidResponse("min_amount_received \(minReceived) is outside the requested slippage")
        }

        // The router call is opaque, but its ABI arguments carry these values as
        // whole words. Requiring them binds the calldata to what was validated
        // above rather than to the response's metadata alone.
        guard Self.hasArgumentWord(calldata, Self.uintWord(amountIn)),
              Self.hasArgumentWord(calldata, Self.uintWord(minReceived)),
              Self.hasArgumentWord(calldata, Self.addressWord(context.recipient)) else {
            throw FyndError.invalidResponse("calldata does not encode the quoted amounts and recipient")
        }

        if context.clientFeeBps == 0 {
            guard clientFee == 0 else {
                throw FyndError.invalidResponse("unexpected client fee \(clientFee)")
            }
        } else {
            try validateClientFee(
                clientFee: clientFee,
                amountOut: amountOut,
                calldata: calldata,
                signatureOffset: tx.clientFeeSignatureOffset,
                deadline: order.clientFeeDeadline,
                context: context
            )
        }

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
        clientFee: BigInt,
        amountOut: BigInt,
        calldata: String,
        signatureOffset: Int?,
        deadline: Int?,
        context: FyndQuoteContext
    ) throws {
        let expected = expectedClientFee(amountOut: amountOut, clientFeeBps: context.clientFeeBps)
        // One unit of rounding either way; more is a different fee than asked.
        guard (clientFee - expected).magnitude <= 1 else {
            throw FyndError.invalidResponse("client fee \(clientFee) does not match \(context.clientFeeBps) bps (expected \(expected))")
        }

        guard hasArgumentWord(calldata, addressWord(context.feeReceiver)) else {
            throw FyndError.invalidResponse("calldata does not name the Vultisig fee receiver")
        }

        let signatureHexLength = clientFeeSignatureBytes * 2
        guard let offset = signatureOffset, offset >= 0,
              calldata.count >= signatureHexLength,
              offset <= (calldata.count - signatureHexLength) / 2 else {
            throw FyndError.invalidResponse("missing client fee signature offset")
        }
        let start = calldata.index(calldata.startIndex, offsetBy: offset * 2)
        let end = calldata.index(start, offsetBy: signatureHexLength)
        guard calldata[start..<end].contains(where: { $0 != "0" }) else {
            throw FyndError.invalidResponse("client fee signature is the unsigned placeholder")
        }

        guard let deadline, TimeInterval(deadline) > context.now.timeIntervalSince1970 else {
            throw FyndError.invalidResponse("client fee deadline missing or expired")
        }
    }

    /// Fynd routes are a few hundred thousand gas; anything far above that is
    /// not a quote we would sign.
    static let maxGasEstimate: Int64 = 10_000_000

    static func uintWord(_ value: BigInt) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    /// Whether `word` is one of the 32-byte argument words after the 4-byte selector.
    static func hasArgumentWord(_ calldata: String, _ word: String) -> Bool {
        guard word.count == 64, calldata.count >= 8 + 64 else { return false }
        var start = calldata.index(calldata.startIndex, offsetBy: 8)
        while calldata.distance(from: start, to: calldata.endIndex) >= 64 {
            let end = calldata.index(start, offsetBy: 64)
            if calldata[start..<end] == word { return true }
            start = end
        }
        return false
    }

    static func addressWord(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.lowercased().stripHexPrefix()
    }

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
