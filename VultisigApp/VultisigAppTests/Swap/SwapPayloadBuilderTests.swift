//
//  SwapPayloadBuilderTests.swift
//  VultisigAppTests
//
//  Structural coverage for `SwapCryptoLogic.buildSwapKeysignPayload(transaction:
//  chainSpecific: vault: now:)` — one assertion per quote shape covering
//  toAddress routing, swapPayload variant wiring, vault propagation, and
//  approvePayload presence.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapPayloadBuilderTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private var expectedExpiration: UInt64 {
        UInt64(fixedNow.addingTimeInterval(60 * 15).timeIntervalSince1970)
    }

    // MARK: - THORChain

    func testThorchainPayloadRoutesThroughInboundAddressForNativeSource() async throws {
        let vault = makeVault()
        let transaction = makeNativeThorchainTransaction(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertEqual(payload.toAddress, "thor-vault")
        XCTAssertEqual(payload.toAmount, BigInt(100_000_000)) // 1.0 RUNE @ 8 decimals
        XCTAssertEqual(payload.memo, "thor-memo")
        XCTAssertEqual(payload.vaultPubKeyECDSA, "test-pub-ecdsa")
        XCTAssertEqual(payload.vaultLocalPartyID, "party")
        XCTAssertNil(payload.approvePayload, "Native source does not require approval")
        guard case let .thorchain(swap) = payload.swapPayload else {
            XCTFail("Expected .thorchain swapPayload variant"); return
        }
        XCTAssertEqual(swap.fromAddress, "test-address-RUNE")
        XCTAssertEqual(swap.vaultAddress, "thor-vault")
        XCTAssertEqual(swap.expirationTime, expectedExpiration)
        XCTAssertTrue(swap.isAffiliate)
    }

    func testThorchainPayloadPrefersRouterWhenPresent() async throws {
        let vault = makeVault()
        let transaction = makeNativeThorchainTransaction(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: "thor-router")
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertEqual(payload.toAddress, "thor-router")
    }

    // MARK: - Memo LIM/INTERVAL/QUANTITY parsing

    func testMemoTermsAutoSlippageMemoAssertsNoFloor() {
        // Real mainnet memo captured from thornode with no tolerance param:
        // the node emits LIM 0, i.e. "no minimum output guaranteed".
        let terms = SwapCryptoLogic.thorchainMemoSwapTerms(
            from: "=:e:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:0/1/0"
        )
        XCTAssertEqual(terms.limit, "0", "Auto slippage carries no LIM — the payload must not claim one")
        XCTAssertEqual(terms.streamingInterval, "1")
        XCTAssertEqual(terms.streamingQuantity, "0")
    }

    func testMemoTermsCustomSlippageParsesNodeLimitExactly() {
        // The node's own floor for tolerance_bps=100 at 0.1 BTC. It is NOT
        // expected_amount_out × 0.99 (that would be 338179686) — which is why
        // this value can only come from the memo.
        let terms = SwapCryptoLogic.thorchainMemoSwapTerms(
            from: "=:e:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:340077095/1/3"
        )
        XCTAssertEqual(terms.limit, "340077095")
        XCTAssertEqual(terms.streamingInterval, "1")
        XCTAssertEqual(terms.streamingQuantity, "3")
    }

    func testMemoTermsIgnoreTrailingAffiliateAndFeeFields() {
        // Affiliate + fee fields sit AFTER the triple, so they must not shift it.
        let terms = SwapCryptoLogic.thorchainMemoSwapTerms(
            from: "=:BTC.BTC:bc1qexampleaddress:12345/2/4:va:50"
        )
        XCTAssertEqual(terms.limit, "12345")
        XCTAssertEqual(terms.streamingInterval, "2")
        XCTAssertEqual(terms.streamingQuantity, "4")
    }

    func testMemoTermsUnabbreviatedSwapPrefixAndMissingStreamingFields() {
        // Full `SWAP:` prefix, rapid swap: LIM present, no `/INTERVAL/QUANTITY`.
        let terms = SwapCryptoLogic.thorchainMemoSwapTerms(
            from: "SWAP:ETH.ETH:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:98765"
        )
        XCTAssertEqual(terms.limit, "98765")
        XCTAssertEqual(terms.streamingInterval, "0", "A memo with no streaming spec is a single swap")
        XCTAssertEqual(terms.streamingQuantity, "0")
    }

    func testMemoTermsSecuredAssetMemoParsesLimit() {
        // Secured-asset notation uses `-` inside the asset field, never `:`,
        // so the triple stays in the 4th field.
        let terms = SwapCryptoLogic.thorchainMemoSwapTerms(
            from: "=:BTC-BTC:thor1exampledestination:777/1/0"
        )
        XCTAssertEqual(terms.limit, "777")
        XCTAssertEqual(terms.streamingInterval, "1")
        XCTAssertEqual(terms.streamingQuantity, "0")
    }

    func testMemoTermsMayaMemoParsesLimit() {
        // Maya memos share the THORChain grammar (CACAO uses 1e10 units, but
        // the parser is unit-agnostic — it mirrors whatever the memo says).
        let terms = SwapCryptoLogic.thorchainMemoSwapTerms(
            from: "=:MAYA.CACAO:maya1exampledestination:338900185/3/0"
        )
        XCTAssertEqual(terms.limit, "338900185")
        XCTAssertEqual(terms.streamingInterval, "3")
        XCTAssertEqual(terms.streamingQuantity, "0")
    }

    func testMemoTermsFallBackToUnspecifiedOnUnusableMemo() {
        // Never fall back to expected_amount_out: "0" honestly says "no floor
        // asserted", a derived number would claim one the memo doesn't carry.
        for memo in [
            "",                                       // no memo at all
            "=:BTC.BTC",                              // truncated before DESTADDR
            "=:BTC.BTC:bc1qexampleaddress",           // no LIM field
            "=:BTC.BTC:bc1qexampleaddress:",          // empty LIM field
            "=:BTC.BTC:bc1qexampleaddress:abc/1/0",   // non-numeric LIM
            "=:BTC.BTC:bc1qexampleaddress:-5/1/0",    // signed LIM
            "=:BTC.BTC:bc1qexampleaddress:1.5/1/0",   // fractional LIM
            "=:BTC.BTC:bc1qexampleaddress: 500/1/0",  // padded LIM is not canonical
            "=:BTC.BTC:bc1qexampleaddress:١٢٣/1/0",   // non-ASCII numerals
            "=:BTC.BTC:bc1qexampleaddress:5/1/0/9"    // more terms than the grammar has
        ] {
            XCTAssertEqual(
                SwapCryptoLogic.thorchainMemoSwapTerms(from: memo), .unspecified,
                "Unusable memo \"\(memo)\" must assert nothing"
            )
        }
    }

    func testMemoTermsRejectNonSwapActions() {
        // Other THORChain actions lay their fields out differently, so their
        // 4th field is not a LIM triple even when it happens to be numeric.
        for memo in [
            "DONATE:BTC.BTC:bc1qexampleaddress:500",
            "ADD:BTC.BTC:bc1qexampleaddress:500/1/0",
            "LOAN+:BTC.BTC:bc1qexampleaddress:500/1/0"
        ] {
            XCTAssertEqual(
                SwapCryptoLogic.thorchainMemoSwapTerms(from: memo), .unspecified,
                "Non-swap memo \"\(memo)\" must not be read as a swap"
            )
        }
    }

    func testMemoTermsAcceptEverySwapActionSpelling() {
        // THORChain spells the swap action `SWAP`, `=` or `s`, case-insensitively.
        for action in ["SWAP", "swap", "=", "s", "S"] {
            XCTAssertEqual(
                SwapCryptoLogic.thorchainMemoSwapTerms(
                    from: "\(action):BTC.BTC:bc1qexampleaddress:500/1/0"
                ).limit,
                "500",
                "\"\(action)\" is a valid swap action spelling"
            )
        }
    }

    func testMemoTermsRejectWholeTripleWhenAnyTermIsUnreadable() {
        // All-or-nothing: a LIM salvaged from a memo whose grammar we failed to
        // parse is exactly the false floor this parser exists to avoid.
        XCTAssertEqual(
            SwapCryptoLogic.thorchainMemoSwapTerms(from: "=:BTC.BTC:bc1qexampleaddress:500/x/7"),
            .unspecified
        )
    }

    // MARK: - Payload wiring of the memo terms

    func testBuildThorchainSwapPayloadTakesLimitAndStreamingFromMemo() {
        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: 1,
            quote: makeThorQuote(
                inboundAddress: "thor-vault",
                router: nil,
                memo: "=:e:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:340077095/1/3"
            ),
            now: fixedNow
        )
        XCTAssertEqual(payload.toAmountLimit, "340077095")
        XCTAssertEqual(payload.streamingInterval, "1")
        XCTAssertEqual(payload.streamingQuantity, "3")
    }

    func testBuildThorchainSwapPayloadReportsNoFloorForAutoSlippage() {
        // The regression this fixes: the old derivation reported 100% of
        // expected_amount_out as a guaranteed floor on every Auto swap.
        let quote = makeThorQuote(
            inboundAddress: "thor-vault",
            router: nil,
            memo: "=:e:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:0/1/0"
        )
        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: 1,
            quote: quote,
            now: fixedNow
        )
        XCTAssertEqual(payload.toAmountLimit, "0")
        XCTAssertNotEqual(
            payload.toAmountLimit, quote.expectedAmountOut,
            "A memo with LIM 0 must never report the full expected output as a floor"
        )
    }

    func testBuildThorchainSwapPayloadIgnoresMaxStreamingQuantityCeiling() {
        // `max_streaming_quantity` is the node's capacity ceiling, not the
        // quantity it baked into the memo — the payload must report the memo's.
        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: 1,
            quote: makeThorQuote(
                inboundAddress: "thor-vault",
                router: nil,
                memo: "=:e:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:0/1/0",
                maxStreamingQuantity: 42
            ),
            now: fixedNow
        )
        XCTAssertEqual(payload.streamingQuantity, "0")
    }

    // MARK: - MayaChain

    func testMayachainPayloadRoutesThroughInboundForNativeSource() async throws {
        let vault = makeVault()
        let transaction = makeNativeMayachainTransaction(
            quote: makeThorQuote(inboundAddress: "maya-vault", router: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertEqual(payload.toAddress, "maya-vault")
        guard case let .mayachain(swap) = payload.swapPayload else {
            XCTFail("Expected .mayachain swapPayload variant"); return
        }
        XCTAssertEqual(swap.expirationTime, expectedExpiration)
    }

    // MARK: - 1Inch / KyberSwap / Lifi

    func testOneInchPayloadUsesEvmTxToAsTarget() async throws {
        let vault = makeVault()
        let transaction = makeERC20Transaction(
            quote: .oneinch(makeEVMQuote(toAddress: "0xOneInchRouter"), fee: BigInt(1_000))
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertEqual(payload.toAddress, "0xOneInchRouter")
        XCTAssertNil(payload.memo, "EVM aggregators don't use memos")
        XCTAssertNotNil(payload.approvePayload, "ERC20 source + router => approve required")
        XCTAssertEqual(payload.approvePayload?.spender, "0xOneInchRouter")
        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.provider, .oneInch)
    }

    func testKyberSwapPayloadProviderIsKyberSwap() async throws {
        let vault = makeVault()
        let transaction = makeERC20Transaction(
            quote: .kyberswap(makeEVMQuote(toAddress: "0xKyber"), fee: BigInt(0))
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.provider, .kyberSwap)
    }

    func testLifiPayloadProviderIsLifi() async throws {
        let vault = makeVault()
        let transaction = makeERC20Transaction(
            quote: .lifi(makeEVMQuote(toAddress: "0xLifi"), fee: BigInt(0), integratorFee: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.provider, .lifi)
    }

    // MARK: - Jupiter (Solana)

    func testJupiterPayloadIsGenericSolanaWithBase64InTxData() async throws {
        let vault = makeVault()
        let transaction = makeSolanaJupiterTransaction(
            quote: .jupiter(
                makeSolanaEVMQuote(base64: "AQIDBA=="),
                fee: nil,
                platformFee: Decimal(string: "0.5")
            )
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: solanaChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertNil(payload.memo, "Solana swaps don't use memos")
        XCTAssertNil(payload.approvePayload, "Solana never needs an ERC20 approve")
        XCTAssertEqual(payload.toAddress, "SoLoutputMint", "Jupiter toAddress is the cosmetic EVMQuote.tx.to (the output mint, as JupiterService sets it)")
        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.provider, .jupiter)
        XCTAssertEqual(
            generic.quote.tx.data, "AQIDBA==",
            "Base64 Solana wire tx must ride verbatim in quote.tx.data (the SwapKit-Solana MPC path)"
        )
    }

    // MARK: - Swap-fee coin context

    func testKyberSwapPayloadCarriesDestinationTokenFeeContext() async throws {
        // KyberSwap denominates the affiliate fee in the destination token
        // (chargeFeeBy: "currency_out") — the serialized context must point
        // at toCoin so the co-signer doesn't misread a 6-decimal token
        // amount as an 18-decimal native one.
        let vault = makeVault()
        let transaction = makeNativeToTokenTransaction(
            quote: .kyberswap(
                makeEVMQuote(
                    toAddress: "0xKyber",
                    swapFee: "5000000",
                    swapFeeTokenContract: usdcContract
                ),
                fee: BigInt(1_000)
            )
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.swapFeeChain, "Ethereum")
        XCTAssertEqual(generic.swapFeeTokenId, usdcContract)
        XCTAssertEqual(generic.swapFeeDecimals, 6)
    }

    func testLifiPayloadCarriesQuoteDeclaredTokenFeeContext() async throws {
        // LiFi declares the fee token on the quote; here it matches the
        // source token.
        let vault = makeVault()
        let transaction = makeTokenToNativeTransaction(
            quote: .lifi(
                makeEVMQuote(
                    toAddress: "0xLifi",
                    swapFee: "250000",
                    swapFeeTokenContract: usdcContract
                ),
                fee: BigInt(1_000),
                integratorFee: nil
            )
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.swapFeeChain, "Ethereum")
        XCTAssertEqual(generic.swapFeeTokenId, usdcContract)
        XCTAssertEqual(generic.swapFeeDecimals, 6)
    }

    func testLifiPayloadNativeFeeContextHasNilTokenId() async throws {
        // No fee-token contract on the quote → fee falls to the chain's
        // native fee coin: empty contract serializes as nil token id with
        // the native coin's decimals.
        let vault = makeVault()
        let transaction = makeTokenToNativeTransaction(
            quote: .lifi(
                makeEVMQuote(
                    toAddress: "0xLifi",
                    swapFee: "10000000000000000",
                    swapFeeTokenContract: ""
                ),
                fee: BigInt(1_000),
                integratorFee: nil
            )
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.swapFeeChain, "Ethereum")
        XCTAssertNil(generic.swapFeeTokenId)
        XCTAssertEqual(generic.swapFeeDecimals, 18)
    }

    func testOneInchZeroSwapFeeLeavesFeeContextNil() async throws {
        let vault = makeVault()
        let transaction = makeNativeToTokenTransaction(
            quote: .oneinch(
                makeEVMQuote(toAddress: "0x1inch", swapFee: "0", swapFeeTokenContract: ""),
                fee: BigInt(1_000)
            )
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertNil(generic.swapFeeChain)
        XCTAssertNil(generic.swapFeeTokenId)
        XCTAssertNil(generic.swapFeeDecimals)
    }

    // MARK: - Approve gating

    func testApprovePayloadNilForNativeSource() async throws {
        let vault = makeVault()
        let transaction = makeNativeThorchainTransaction(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertNil(payload.approvePayload)
    }

    func testBuildApprovePayloadNilWhenQuoteAbsent() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        XCTAssertNil(SwapCryptoLogic.buildApprovePayload(fromCoin: usdc, amount: 100, quote: nil))
    }

    // MARK: - Fixtures

    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func makeNativeThorchainTransaction(quote: ThorchainSwapQuote) -> SwapTransaction {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        return SwapTransaction(
            fromCoin: rune,
            toCoin: btc,
            fromAmount: 1.0,
            kind: .market(.thorchain(quote)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: BigInt(2_000),
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: rune,            advancedSettings: .default
        )
    }

    private func makeNativeMayachainTransaction(quote: ThorchainSwapQuote) -> SwapTransaction {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        return SwapTransaction(
            fromCoin: cacao,
            toCoin: btc,
            fromAmount: 1.0,
            kind: .market(.mayachain(quote)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: BigInt(2_000),
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: cacao,            advancedSettings: .default
        )
    }

    private func makeERC20Transaction(quote: SwapQuote) -> SwapTransaction {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        return SwapTransaction(
            fromCoin: usdc,
            toCoin: eth,
            fromAmount: 100,
            kind: .market(quote),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,            advancedSettings: .default
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    /// Real-shaped contract address so swap-fee context tests exercise the
    /// case-insensitive token-id match against an actual hex string.
    private let usdcContract = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    /// Coin with an explicit contract address (empty for natives) — the
    /// swap-fee context serializes `contractAddress.nilIfEmpty`, so these
    /// fixtures must not carry the placeholder "<TICKER>-contract".
    private func makeContractCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeNativeToTokenTransaction(quote: SwapQuote) -> SwapTransaction {
        let eth = makeContractCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, contract: "")
        let usdc = makeContractCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: usdcContract)
        return SwapTransaction(
            fromCoin: eth,
            toCoin: usdc,
            fromAmount: 1.0,
            kind: .market(quote),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,            advancedSettings: .default
        )
    }

    private func makeTokenToNativeTransaction(quote: SwapQuote) -> SwapTransaction {
        let eth = makeContractCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, contract: "")
        let usdc = makeContractCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: usdcContract)
        return SwapTransaction(
            fromCoin: usdc,
            toCoin: eth,
            fromAmount: 100,
            kind: .market(quote),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,            advancedSettings: .default
        )
    }

    private func makeThorQuote(
        inboundAddress: String?,
        router: String?,
        memo: String = "thor-memo",
        maxStreamingQuantity: Int? = nil
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: inboundAddress,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: router,
            maxStreamingQuantity: maxStreamingQuantity
        )
    }

    private func makeEVMQuote(
        toAddress: String,
        swapFee: String = "0",
        swapFeeTokenContract: String = ""
    ) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000000000000000",
            tx: EVMQuote.Transaction(
                from: "0xFrom",
                to: toAddress,
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0,
                swapFee: swapFee,
                swapFeeTokenContract: swapFeeTokenContract
            )
        )
    }

    private func makeSolanaJupiterTransaction(quote: SwapQuote) -> SwapTransaction {
        let sol = makeContractCoin(.solana, ticker: "SOL", decimals: 9, isNative: true, contract: "")
        let usdc = makeContractCoin(
            .solana, ticker: "USDC", decimals: 6, isNative: false,
            contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        )
        return SwapTransaction(
            fromCoin: sol,
            toCoin: usdc,
            fromAmount: 1.0,
            kind: .market(quote),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: sol,            advancedSettings: .default
        )
    }

    private func makeSolanaEVMQuote(base64: String) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: "SoLfromAddr",
                to: "SoLoutputMint",
                data: base64,
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
    }

    private func solanaChainSpecific() -> BlockChainSpecific {
        .Solana(
            recentBlockHash: "blockhash",
            priorityFee: BigInt(0),
            priorityLimit: BigInt(0),
            fromAddressPubKey: nil,
            toAddressPubKey: nil,
            hasProgramId: false
        )
    }

    private func cosmosChainSpecific() -> BlockChainSpecific {
        .Cosmos(accountNumber: 1, sequence: 0, gas: 200_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }

    private func ethereumChainSpecific() -> BlockChainSpecific {
        .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 1, gasLimit: BigInt(300_000))
    }
}
