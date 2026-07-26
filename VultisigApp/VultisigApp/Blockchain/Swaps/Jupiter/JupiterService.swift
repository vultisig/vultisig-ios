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
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "jupiter-service")

struct JupiterService {

    static let shared = JupiterService()

    /// Self-owned fee wallet. The affiliate fee accrues to this owner's
    /// per-output-mint Associated Token Account (one ATA per mint, shared by all
    /// users). We never use Jupiter's on-chain Referral Program.
    static let feeOwner = "8iqhrtBzMcYLR6c6FkzeoMHibedYDkHvLKnX2ArNie5z"

    /// Wrapped-SOL mint — the mint Jupiter uses for native SOL on both legs.
    static let wrappedSolMint = "So11111111111111111111111111111111111111112"

    /// Default slippage (0.5%) when the user hasn't chosen a custom value.
    static let defaultSlippageBps = 50

    /// Compute-unit price (micro-lamports) requested on `/swap` so Jupiter bakes
    /// a priority fee into the returned transaction. Mirrors Android's
    /// `MIN_FEE_PRICE_SWAP`.
    static let computeUnitPriceMicroLamports = 150_000

    private let httpClient: HTTPClientProtocol
    private let solanaService: SolanaService

    init(httpClient: HTTPClientProtocol = HTTPClient(), solanaService: SolanaService = .shared) {
        self.httpClient = httpClient
        self.solanaService = solanaService
    }

    /// Fetch a Jupiter quote + swap transaction for a same-chain Solana pair.
    /// Returns the `EVMQuote` carrying the base64 wire tx in `tx.data`, the
    /// (Solana) network fee (unknown at quote time → `nil`), and the affiliate
    /// platform fee in `toCoin` units (subtracted in ranking).
    ///
    /// Affiliate fee is provisioned OFF the signed path (see the plan): we derive
    /// the fee ATA address, do a read-only on-chain existence pre-check, and pass
    /// `platformFeeBps` + `feeAccount` to Jupiter. We NEVER build or inject an
    /// ATA-create instruction. If the fee ATA isn't provisioned yet, Jupiter is
    /// dropped for this pair (the quote throws) and LiFi — which also collects
    /// the affiliate fee — serves it instead.
    func fetchQuote(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: BigInt,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> (quote: EVMQuote, fee: BigInt?, platformFee: Decimal, feeOnInput: Bool) {
        let inputMint = jupiterMint(for: fromCoin)
        let outputMint = jupiterMint(for: toCoin)

        // Same numerator LiFi/Kyber/SwapKit use: 50 bps, reduced by the VULT
        // tier discount, floored at 0.
        let platformFeeBps = Self.platformFeeBps(vultTierDiscount: vultTierDiscount)

        let feeMint = Self.feeMint(inputMint: inputMint, outputMint: outputMint)

        // Derive + verify the fee ATA off the signed path. Skip entirely when
        // there's no fee to collect (fully-discounted user).
        let feeAccount = platformFeeBps > 0
            ? try await resolveFeeAccount(mint: feeMint)
            : nil

        let params = JupiterQuoteParams(
            inputMint: inputMint,
            outputMint: outputMint,
            amount: String(fromAmount),
            slippageBps: slippageBps ?? Self.defaultSlippageBps,
            platformFeeBps: platformFeeBps > 0 ? platformFeeBps : nil
        )

        let quoteData = try await fetchQuoteData(params: params)
        let quoteResponse = try JSONDecoder().decode(JupiterQuoteResponse.self, from: quoteData)

        // Reject a response that quoted a different pair than requested — a
        // mismatched proxy/Jupiter quote must never be ranked or signed as if
        // it swapped into `toCoin`.
        guard quoteResponse.inputMint == inputMint,
              quoteResponse.outputMint == outputMint,
              let outAmount = BigInt(quoteResponse.outAmount), outAmount > 0 else {
            throw JupiterError.invalidQuote
        }

        let swapBase64 = try await fetchSwapTransaction(
            quoteData: quoteData,
            userPublicKey: fromCoin.address,
            feeAccount: feeAccount
        )

        // `platformFee` is denominated in the fee mint. It's surfaceable in
        // `toCoin` units only when the fee mint IS the output mint. For the
        // input-mint case (native-SOL outputs) it would be mis-denominated, so
        // it's flagged `feeOnInput` and reported as 0 — display suppresses the
        // affiliate row there rather than show a misleading amount. A zero
        // output-mint fee (Ultimate tier) is a real 0, shown as a $0.00 row.
        // Ranking uses `outAmount` (already net of the fee) regardless.
        let feeOnInput = feeMint != outputMint
        let platformFee: Decimal = feeOnInput ? .zero : (platformFeeDecimal(from: quoteResponse, toCoin: toCoin) ?? .zero)

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
        return (evmQuote, nil, platformFee, feeOnInput)
    }

    /// The mint Jupiter expects for a coin: the SPL contract address, or wrapped
    /// SOL for native SOL.
    func jupiterMint(for coin: Coin) -> String {
        coin.isNativeToken ? Self.wrappedSolMint : coin.contractAddress
    }

    /// Affiliate fee in basis points: the same 50bps base LiFi/Kyber/SwapKit use,
    /// reduced by the VULT tier discount and floored at 0.
    static func platformFeeBps(vultTierDiscount: Int) -> Int {
        max(0, LiFiService.integratorFeeBps - vultTierDiscount)
    }

    /// The mint the affiliate fee is collected in. For ExactIn, Jupiter allows
    /// the fee account to be the input OR output mint. We use the output mint,
    /// except for native-SOL outputs (wrapped SOL) where the fee owner holds no
    /// wSOL ATA and collecting in wSOL would need unwrapping — there we charge
    /// the fee on the input mint instead, which works today without provisioning
    /// a wSOL fee ATA.
    static func feeMint(inputMint: String, outputMint: String) -> String {
        outputMint == wrappedSolMint ? inputMint : outputMint
    }
}

private extension JupiterService {

    /// Derive the fee owner's ATA for the fee mint and verify it exists
    /// on-chain (read-only, off the signed path). Token-2022 mints derive a
    /// different ATA, detected by inspecting the mint account's owning program.
    /// Throws `feeAccountNotProvisioned` when the ATA isn't seeded yet so the
    /// fan-out drops Jupiter and LiFi serves the pair.
    func resolveFeeAccount(mint: String) async throws -> String {
        // The mint account's owner program tells us whether it's Token-2022.
        let (mintExists, isToken2022) = try await solanaService.checkAccountExists(address: mint)
        guard mintExists else {
            logger.info("[jupiter] fee mint \(mint, privacy: .public) not found on-chain → drop Jupiter")
            throw JupiterError.feeAccountUnavailable
        }

        guard let owner = WalletCore.SolanaAddress(string: Self.feeOwner) else {
            throw JupiterError.feeAccountUnavailable
        }
        let derived = isToken2022
            ? owner.token2022Address(tokenMintAddress: mint)
            : owner.defaultTokenAddress(tokenMintAddress: mint)
        guard let feeAccount = derived, !feeAccount.isEmpty else {
            throw JupiterError.feeAccountUnavailable
        }

        // Read-only existence pre-check: never route to Jupiter unless we can
        // collect the fee into an already-provisioned ATA.
        let (feeAtaExists, _) = try await solanaService.checkAccountExists(address: feeAccount)
        guard feeAtaExists else {
            logger.info("[jupiter] fee ATA \(feeAccount, privacy: .public) not provisioned → drop Jupiter, fall back to LiFi")
            throw JupiterError.feeAccountNotProvisioned
        }
        return feeAccount
    }

    /// The affiliate platform fee in `toCoin` units, from Jupiter's
    /// `platformFee.amount` (output-mint raw base units). `nil` when no fee was
    /// charged.
    func platformFeeDecimal(from response: JupiterQuoteResponse, toCoin: Coin) -> Decimal? {
        guard let amountStr = response.platformFee?.amount,
              let amount = BigInt(amountStr), amount > 0 else {
            return nil
        }
        return toCoin.decimal(for: amount)
    }

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
