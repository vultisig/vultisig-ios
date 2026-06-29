//
//  JupiterService.swift
//  VultisigApp
//
//  Jupiter Solana swap provider. Fetches a Jupiter quote and the matching
//  base64 Solana wire transaction, returned in the `EVMQuote` shape so the swap
//  rides the proven SwapKit-Solana signing path (`SwapPayload.generic` →
//  `SolanaSwaps`, which refreshes only the recent blockhash in place). Jupiter
//  is Solana-only and same-chain; cross-chain pairs never reach it because the
//  `SwapCoinsResolver` intersects the from/to provider lists.
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "jupiter-service")

struct JupiterService {

    static let shared = JupiterService()

    /// Wrapped-SOL mint — the mint Jupiter uses for native SOL on both legs.
    static let wrappedSolMint = "So11111111111111111111111111111111111111112"

    /// Default slippage (0.5%) when the user hasn't chosen a custom value.
    static let defaultSlippageBps = 50

    /// Compute-unit price (micro-lamports) requested on `/swap` so Jupiter bakes
    /// a priority fee into the returned transaction. Mirrors Android's
    /// `MIN_FEE_PRICE_SWAP`.
    static let computeUnitPriceMicroLamports = 150_000

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Fetch a Jupiter quote + swap transaction for a same-chain Solana pair.
    /// Returns the `EVMQuote` carrying the base64 wire tx in `tx.data`, the
    /// (Solana) network fee (unknown at quote time → `nil`), and the affiliate
    /// platform fee in `toCoin` units (Phase 1: always `nil` — no fee yet).
    func fetchQuote(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: BigInt,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> (quote: EVMQuote, fee: BigInt?, platformFee: Decimal?) {
        let inputMint = jupiterMint(for: fromCoin)
        let outputMint = jupiterMint(for: toCoin)

        let params = JupiterQuoteParams(
            inputMint: inputMint,
            outputMint: outputMint,
            amount: String(fromAmount),
            slippageBps: slippageBps ?? Self.defaultSlippageBps,
            platformFeeBps: nil
        )

        let quoteData = try await fetchQuoteData(params: params)
        let quoteResponse = try JSONDecoder().decode(JupiterQuoteResponse.self, from: quoteData)

        guard let outAmount = BigInt(quoteResponse.outAmount), outAmount > 0 else {
            throw JupiterError.invalidQuote
        }

        let swapBase64 = try await fetchSwapTransaction(
            quoteData: quoteData,
            userPublicKey: fromCoin.address,
            feeAccount: nil
        )

        let evmQuote = EVMQuote(
            dstAmount: quoteResponse.outAmount,
            tx: EVMQuote.Transaction(
                from: fromCoin.address,
                to: outputMint,
                data: swapBase64,
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
        return (evmQuote, nil, nil)
    }

    /// The mint Jupiter expects for a coin: the SPL contract address, or wrapped
    /// SOL for native SOL.
    func jupiterMint(for coin: Coin) -> String {
        coin.isNativeToken ? Self.wrappedSolMint : coin.contractAddress
    }
}

private extension JupiterService {

    func fetchQuoteData(params: JupiterQuoteParams) async throws -> Data {
        do {
            return try await httpClient.request(JupiterAPI.quote(params)).data
        } catch HTTPError.statusCode(let code, _) {
            throw JupiterError.quoteFailed(statusCode: code)
        }
    }

    /// Build the `/swap` body around the verbatim quote JSON and POST it.
    func fetchSwapTransaction(
        quoteData: Data,
        userPublicKey: String,
        feeAccount: String?
    ) async throws -> String {
        guard let quoteObject = try? JSONSerialization.jsonObject(with: quoteData) else {
            throw JupiterError.invalidQuote
        }

        var body: [String: Any] = [
            "quoteResponse": quoteObject,
            "userPublicKey": userPublicKey,
            "wrapAndUnwrapSol": true,
            "dynamicComputeUnitLimit": true,
            "computeUnitPriceMicroLamports": Self.computeUnitPriceMicroLamports
        ]
        if let feeAccount {
            body["feeAccount"] = feeAccount
        }

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw JupiterError.invalidQuote
        }

        do {
            let response = try await httpClient.request(
                JupiterAPI.swap(body: bodyData),
                responseType: JupiterSwapResponse.self
            )
            return response.data.swapTransaction
        } catch HTTPError.statusCode(let code, _) {
            throw JupiterError.swapFailed(statusCode: code)
        }
    }
}

enum JupiterError: Error, Equatable {
    case invalidQuote
    case quoteFailed(statusCode: Int)
    case swapFailed(statusCode: Int)
    /// The output mint could not be resolved on-chain (Token-2022 detection /
    /// ATA derivation failed).
    case feeAccountUnavailable
    /// The affiliate fee ATA for the output mint is not yet provisioned
    /// on-chain. Jupiter is dropped for this pair so LiFi (which also collects
    /// the affiliate fee) serves it instead. Provisioning is a backend
    /// responsibility (see the plan); this is expected, not a failure.
    case feeAccountNotProvisioned
}
