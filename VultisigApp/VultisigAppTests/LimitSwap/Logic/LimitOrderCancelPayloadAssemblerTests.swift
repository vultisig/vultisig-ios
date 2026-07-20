//
//  LimitOrderCancelPayloadAssemblerTests.swift
//  VultisigAppTests
//
//  The parts of L1 cancel assembly that are decidable without a network: the
//  memo-length gate and the dust computation against a real inbound row.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelPayloadAssemblerTests: XCTestCase {

    private func makeCoin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "addr", hexPublicKey: "HexPublicKeyExample")
    }

    private func makeInbound(
        chain: String,
        dustThreshold: String?,
        halted: Bool = false
    ) -> InboundAddress {
        InboundAddress(
            chain: chain,
            address: "inbound-address",
            router: nil,
            halted: halted,
            global_trading_paused: false,
            chain_trading_paused: false,
            chain_lp_actions_paused: false,
            gas_rate: "10",
            gas_rate_units: "satsperbyte",
            dust_threshold: dustThreshold,
            outbound_fee: "1000",
            outbound_tx_size: "1"
        )
    }

    // MARK: - Dust resolution against a real inbound row

    func testBitcoinDustComesFromTheInboundThreshold() throws {
        let coin = makeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)
        let dust = try limitOrderCancelDust(for: coin, inbound: makeInbound(chain: "BTC", dustThreshold: "1000"))

        XCTAssertEqual(dust, BigInt(2000))
    }

    /// DOGE is the case worth naming: a 1 DOGE minimum means 2 whole DOGE are
    /// donated per cancel, which the confirmation UI has to state outright.
    func testDogeDustIsTwoWholeCoins() throws {
        let coin = makeCoin(chain: .dogecoin, ticker: "DOGE", decimals: 8)
        let dust = try limitOrderCancelDust(for: coin, inbound: makeInbound(chain: "DOGE", dustThreshold: "100000000"))

        XCTAssertEqual(dust, BigInt(200_000_000))
        XCTAssertEqual(coin.decimal(for: dust), 2)
    }

    /// ⚠️ Fails closed rather than defaulting. A guess below THORChain's real
    /// threshold is ignored by Bifrost: the transaction confirms on the source
    /// chain, the fee is spent, and nothing is cancelled.
    func testMissingInboundThresholdFailsClosed() {
        let coin = makeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)

        XCTAssertThrowsError(
            try limitOrderCancelDust(for: coin, inbound: makeInbound(chain: "BTC", dustThreshold: nil))
        ) { error in
            guard case .dust(.inboundDustThresholdUnavailable) = error as? LimitOrderCancelAssemblyError else {
                return XCTFail("expected a dust-unavailable failure, got \(error)")
            }
        }
    }

    /// The remote threshold cannot decide to donate an arbitrary amount.
    func testAnAbsurdInboundThresholdIsRejected() {
        let coin = makeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)

        XCTAssertThrowsError(
            try limitOrderCancelDust(
                for: coin,
                inbound: makeInbound(chain: "BTC", dustThreshold: "500000000")
            )
        ) { error in
            guard case .dust(.dustAmountExceedsCeiling) = error as? LimitOrderCancelAssemblyError else {
                return XCTFail("expected a ceiling failure, got \(error)")
            }
        }
    }

    // MARK: - Memo gate

    /// A gas-asset cancel fits every chain, including the 80-byte UTXO cap.
    func testGasAssetCancelFitsAUtxoSource() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(100_000_000),
                targetAsset: "ETH.ETH",
                tradeTarget: BigInt(15_979_057_441)
            )
        )

        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: Chain.bitcoin.chainType))
    }

    /// The combination v1 blocks. Nothing in a cancel memo can be shortened —
    /// the amounts define the ratio bucket, short codes are rejected by
    /// `cosmos.ParseCoins`, and this memo type skips `fuzzyAssetMatch` — so this
    /// is a hard no, not a fitting problem.
    func testErc20TargetFromUtxoSourceIsRejectedByTheGate() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(123_456_789),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(9_876_543_210)
            )
        )

        XCTAssertFalse(limitOrderCancelMemoFits(memo, sourceChainKind: Chain.bitcoin.chainType))
        // …and is fine from an EVM source, which is why this is a per-source
        // gate rather than a property of the order.
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: Chain.ethereum.chainType))
    }

    // MARK: - Routability

    func testNonRoutableSourceChainIsRejected() async {
        do {
            _ = try await resolveThorchainInboundVault(for: .solana)
            XCTFail("expected a routability failure")
        } catch let error as LimitOrderCancelAssemblyError {
            XCTAssertEqual(error, .sourceChainNotRoutable(.solana))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
