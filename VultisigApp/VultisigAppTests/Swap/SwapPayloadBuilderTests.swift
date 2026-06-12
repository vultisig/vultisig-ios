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

    // MARK: - Minimum-output limit (toAmountLimit) derivation

    func testThorchainToAmountLimitAppliesTolerance() {
        // 1% (100 bps) tolerance off 100_000_000 → 99_000_000.
        let limit = SwapCryptoLogic.thorchainToAmountLimit(
            expectedAmountOut: "100000000",
            toleranceBps: 100
        )
        XCTAssertEqual(limit, "99000000")
    }

    func testThorchainToAmountLimitFloorsFractionalResult() {
        // 100 bps off 12_345 = 12_221.55 → floored to 12_221.
        let limit = SwapCryptoLogic.thorchainToAmountLimit(
            expectedAmountOut: "12345",
            toleranceBps: 100
        )
        XCTAssertEqual(limit, "12221")
    }

    func testThorchainToAmountLimitZeroToleranceKeepsFullAmount() {
        let limit = SwapCryptoLogic.thorchainToAmountLimit(
            expectedAmountOut: "500",
            toleranceBps: 0
        )
        XCTAssertEqual(limit, "500")
    }

    func testThorchainToAmountLimitFallsBackToZeroOnBadInput() {
        XCTAssertEqual(
            SwapCryptoLogic.thorchainToAmountLimit(expectedAmountOut: "not-a-number", toleranceBps: 100),
            "0"
        )
        XCTAssertEqual(
            SwapCryptoLogic.thorchainToAmountLimit(expectedAmountOut: "0", toleranceBps: 100),
            "0"
        )
        XCTAssertEqual(
            SwapCryptoLogic.thorchainToAmountLimit(expectedAmountOut: "1000", toleranceBps: 10_000),
            "0",
            "100% tolerance is out of range and must not zero the floor silently to a wrong value"
        )
    }

    func testBuildThorchainSwapPayloadSetsNonZeroLimit() {
        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            toCoin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: 1,
            quote: makeThorQuote(inboundAddress: "thor-vault", router: nil),
            provider: .thorchain,
            toleranceBps: 100,
            now: fixedNow
        )
        XCTAssertNotEqual(payload.toAmountLimit, "0", "Payload must carry a real minimum-output limit, not 0")
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
            quote: .thorchain(quote),
            gas: 0,
            thorchainFee: BigInt(2_000),
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: rune
        )
    }

    private func makeNativeMayachainTransaction(quote: ThorchainSwapQuote) -> SwapTransaction {
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        return SwapTransaction(
            fromCoin: cacao,
            toCoin: btc,
            fromAmount: 1.0,
            quote: .mayachain(quote),
            gas: 0,
            thorchainFee: BigInt(2_000),
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: cacao
        )
    }

    private func makeERC20Transaction(quote: SwapQuote) -> SwapTransaction {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        return SwapTransaction(
            fromCoin: usdc,
            toCoin: eth,
            fromAmount: 100,
            quote: quote,
            gas: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth
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
            quote: quote,
            gas: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth
        )
    }

    private func makeTokenToNativeTransaction(quote: SwapQuote) -> SwapTransaction {
        let eth = makeContractCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, contract: "")
        let usdc = makeContractCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: usdcContract)
        return SwapTransaction(
            fromCoin: usdc,
            toCoin: eth,
            fromAmount: 100,
            quote: quote,
            gas: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth
        )
    }

    private func makeThorQuote(
        inboundAddress: String?,
        router: String?
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "RUNE", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: inboundAddress,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "thor-memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: router,
            maxStreamingQuantity: nil
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

    private func cosmosChainSpecific() -> BlockChainSpecific {
        .Cosmos(accountNumber: 1, sequence: 0, gas: 200_000, transactionType: 0, ibcDenomTrace: nil)
    }

    private func ethereumChainSpecific() -> BlockChainSpecific {
        .Ethereum(maxFeePerGasWei: BigInt(2_000_000_000), priorityFeeWei: BigInt(1_000_000_000), nonce: 1, gasLimit: BigInt(300_000))
    }
}
