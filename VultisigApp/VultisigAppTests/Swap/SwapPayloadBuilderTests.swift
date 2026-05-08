//
//  SwapPayloadBuilderTests.swift
//  VultisigAppTests
//
//  Structural coverage for `SwapCryptoLogic.buildSwapKeysignPayload(draft:
//  chainSpecific: vault: now:)` — one assertion per quote shape covering
//  toAddress routing, swapPayload variant wiring, vault propagation, and
//  approvePayload presence. Goldens skipped per the §1.4 sequencing call;
//  drift caught by the existing per-helper tests + these structural shapes.
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
        let draft = makeNativeThorchainSwapDraft(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        // For thorchain, the spec is: router ?? inboundAddress ?? fromCoin.address.
        // Native source with no router should land on inboundAddress.
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
        let draft = makeNativeThorchainSwapDraft(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: "thor-router")
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertEqual(payload.toAddress, "thor-router")
    }

    // MARK: - MayaChain

    func testMayachainPayloadRoutesThroughInboundForNativeSource() async throws {
        let vault = makeVault()
        let draft = makeNativeMayachainSwapDraft(
            quote: makeThorQuote(inboundAddress: "maya-vault", router: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        // Maya's branch: native source -> inboundAddress.
        XCTAssertEqual(payload.toAddress, "maya-vault")
        guard case let .mayachain(swap) = payload.swapPayload else {
            XCTFail("Expected .mayachain swapPayload variant"); return
        }
        XCTAssertEqual(swap.expirationTime, expectedExpiration)
    }

    // MARK: - 1Inch / KyberSwap / Lifi (EVM aggregators)

    func testOneInchPayloadUsesEvmTxToAsTarget() async throws {
        let vault = makeVault()
        let draft = makeERC20SwapDraft(
            quote: .oneinch(makeEVMQuote(toAddress: "0xOneInchRouter"), fee: BigInt(1_000))
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
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
        let draft = makeERC20SwapDraft(
            quote: .kyberswap(makeEVMQuote(toAddress: "0xKyber"), fee: BigInt(0))
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
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
        let draft = makeERC20SwapDraft(
            quote: .lifi(makeEVMQuote(toAddress: "0xLifi"), fee: BigInt(0), integratorFee: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
            chainSpecific: ethereumChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        guard case let .generic(generic) = payload.swapPayload else {
            XCTFail("Expected .generic swapPayload"); return
        }
        XCTAssertEqual(generic.provider, .lifi)
    }

    // MARK: - Approve gating

    func testApprovePayloadNilForNativeSource() async throws {
        let vault = makeVault()
        let draft = makeNativeThorchainSwapDraft(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: nil)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            draft: draft,
            chainSpecific: cosmosChainSpecific(),
            vault: vault,
            now: fixedNow
        )

        XCTAssertNil(payload.approvePayload)
    }

    func testBuildApprovePayloadNilWhenQuoteAbsent() {
        // EVM aggregator quotes always carry a router (tx.to), so the realistic "no
        // approve" case for an ERC20 source is when the quote hasn't loaded yet.
        var draft = makeERC20SwapDraft(
            quote: .oneinch(makeEVMQuote(toAddress: "0xR"), fee: nil)
        )
        draft.quote = nil
        XCTAssertNil(SwapCryptoLogic.buildApprovePayload(draft: draft))
    }

    // MARK: - Error path

    func testBuildSwapKeysignPayloadThrowsWhenQuoteNil() async {
        let vault = makeVault()
        var draft = makeNativeThorchainSwapDraft(
            quote: makeThorQuote(inboundAddress: "thor-vault", router: nil)
        )
        draft.quote = nil

        do {
            _ = try await SwapCryptoLogic.buildSwapKeysignPayload(
                draft: draft,
                chainSpecific: cosmosChainSpecific(),
                vault: vault,
                now: fixedNow
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? SwapCryptoLogic.Errors, .unexpectedError)
        }
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

    private func makeNativeThorchainSwapDraft(quote: ThorchainSwapQuote) -> SwapDraft {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        draft.toCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        draft.fromAmount = "1.0"
        draft.thorchainFee = BigInt(2_000)
        draft.quote = .thorchain(quote)
        return draft
    }

    private func makeNativeMayachainSwapDraft(quote: ThorchainSwapQuote) -> SwapDraft {
        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        draft.toCoin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        draft.fromAmount = "1.0"
        draft.thorchainFee = BigInt(2_000)
        draft.quote = .mayachain(quote)
        return draft
    }

    private func makeERC20SwapDraft(quote: SwapQuote) -> SwapDraft {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        var draft = SwapDraft()
        draft.fromCoin = usdc
        draft.fromCoins = [usdc, eth]
        draft.toCoin = eth
        draft.fromAmount = "100"
        draft.thorchainFee = BigInt(0)
        draft.quote = quote
        return draft
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeThorQuote(
        inboundAddress: String?,
        router: String?
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(
                affiliate: "0",
                asset: "RUNE",
                outbound: "0",
                total: "0",
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
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

    private func makeEVMQuote(toAddress: String) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000000000000000",
            tx: EVMQuote.Transaction(
                from: "0xFrom",
                to: toAddress,
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0
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
