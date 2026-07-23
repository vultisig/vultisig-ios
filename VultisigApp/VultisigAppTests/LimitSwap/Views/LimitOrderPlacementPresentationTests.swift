//
//  LimitOrderPlacementPresentationTests.swift
//  VultisigAppTests
//
//  What a CO-SIGNER's Verify screen says a limit-order PLACEMENT is.
//
//  A co-signing device holds only a `KeysignPayload`; the `=<:` memo is the sole
//  record that its deposit places a resting order rather than a market swap.
//  Without this, the co-signer falls back to the generic simulation hero and sees
//  an ordinary deposit — the blind-signing risk this parity closes. These pin the
//  memo → (title / from → min-payout / target price / expiry) reconstruction
//  against the same wire vectors the memo BUILDER is pinned to, so display and
//  signed order can't drift.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderPlacementPresentationTests: XCTestCase {

    // MARK: - Hero

    /// A placement gets a swap-shaped hero: the limit title above source →
    /// minimum payout, reconstructed from the memo LIM and the deposited amount.
    func testAPlacementGetsASwapHeroWithTheLimitTitle() {
        // 1 BTC → ETH at 16 ETH/BTC, 12h. LIM 16e8 = 16 ETH minimum.
        let display = LimitOrderPlacementPresentation.display(
            for: makePlacementPayload(
                memo: "=<:ETH.ETH:0x1234567890abcdef1234567890abcdef12345678:16e8/7200/0:vi:50",
                coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                toAmount: 100_000_000
            )
        )

        guard case let .swap(title, from, to)? = display?.hero else {
            return XCTFail("expected a swap hero for a placement")
        }
        XCTAssertEqual(title, "limitSwap.verify.title".localized)
        XCTAssertEqual(from.amount, "1")
        XCTAssertEqual(from.ticker, "BTC")
        XCTAssertEqual(from.logo, "btc")
        XCTAssertEqual(to.amount, "16")
        XCTAssertEqual(to.ticker, "ETH")
        // A co-signer has no target coin, so no target logo is invented.
        XCTAssertEqual(to.logo, "")
    }

    /// The target price is reconstructed as `minOutput ÷ sourceAmount` — the
    /// order's guaranteed floor — and the expiry from the memo's block interval.
    func testTheTargetPriceAndExpiryAreReconstructed() {
        let display = LimitOrderPlacementPresentation.display(
            for: makePlacementPayload(
                memo: "=<:ETH.ETH:0x1234567890abcdef1234567890abcdef12345678:16e8/14400/0:vi:50",
                coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                toAmount: 100_000_000
            )
        )

        XCTAssertEqual(display?.targetPriceValue, "1 BTC = 16 ETH")
        XCTAssertEqual(display?.expiryValue, "24h")
    }

    /// A cheap fractional price against a large token source still reconstructs
    /// exactly: 50000 USDT → BTC, LIM 5e7 = 0.5 BTC ⇒ 0.00001 BTC per USDT.
    func testAFractionalTokenSourcePriceReconstructsExactly() {
        let display = LimitOrderPlacementPresentation.display(
            for: makePlacementPayload(
                memo: "=<:BTC.BTC:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq:5e7/43200/0:vi:50",
                coin: makeCoin(chain: .ethereum, ticker: "USDT", logo: "usdt", decimals: 6, contract: "0xdAC17F958D2ee523a2206206994597C13D831ec7", isNative: false),
                toAmount: 50_000_000_000
            )
        )

        guard case let .swap(_, from, to)? = display?.hero else {
            return XCTFail("expected a swap hero")
        }
        XCTAssertEqual(from.amount, "50,000")
        XCTAssertEqual(to.amount, "0.5")
        XCTAssertEqual(display?.targetPriceValue, "1 USDT = 0.00001 BTC")
        XCTAssertEqual(display?.expiryValue, "72h")
    }

    /// A token TARGET keeps its ticker without the memo's contract suffix.
    func testATokenTargetTickerDropsTheContractSuffix() {
        let display = LimitOrderPlacementPresentation.display(
            for: makePlacementPayload(
                memo: "=<:ETH.USDC-06EB48:0x1234567890abcdef1234567890abcdef12345678:2e8/7200/0:vi:50",
                coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                toAmount: 100_000_000
            )
        )

        guard case let .swap(_, _, to)? = display?.hero else {
            return XCTFail("expected a swap hero")
        }
        XCTAssertEqual(to.ticker, "USDC")
        XCTAssertEqual(display?.targetPriceValue, "1 BTC = 2 USDC")
    }

    // MARK: - Tight gating

    /// A cancel (`m=<:`) is a different memo type and must not be read as a
    /// placement — its own presentation owns it.
    func testACancelMemoIsNotTreatedAsAPlacement() {
        XCTAssertNil(
            LimitOrderPlacementPresentation.display(
                for: makePlacementPayload(
                    memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
                    coin: makeCoin(chain: .thorChain, ticker: "RUNE", logo: "rune", decimals: 8),
                    toAmount: 0
                )
            )
        )
        XCTAssertFalse(LimitOrderPlacementPresentation.isPlacement(memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"))
    }

    /// A market swap (`=>:`) shares neither the prefix nor the presentation.
    func testAMarketSwapMemoIsNotTreatedAsAPlacement() {
        XCTAssertNil(
            LimitOrderPlacementPresentation.display(
                for: makePlacementPayload(
                    memo: "=>:ETH.ETH:0xabc:0/1/0",
                    coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                    toAmount: 100_000_000
                )
            )
        )
        XCTAssertNil(LimitOrderPlacementPresentation.display(for: makePlacementPayload(
            memo: nil,
            coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
            toAmount: 100_000_000
        )))
    }

    /// A zero deposited amount can't yield a price — no display rather than a
    /// divide-by-zero or a nonsense figure.
    func testAZeroAmountPlacementHasNoDisplay() {
        XCTAssertNil(
            LimitOrderPlacementPresentation.display(
                for: makePlacementPayload(
                    memo: "=<:ETH.ETH:0xabc:16e8/7200/0:vi:50",
                    coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                    toAmount: 0
                )
            )
        )
    }

    // MARK: - Hardening (memo is attacker-influenced over the wire)

    /// An interval that isn't a whole number of hours (no order this app builds)
    /// omits the expiry rather than floor it — but the faithful title, pair and
    /// price still show.
    func testANonHourIntervalOmitsExpiryButKeepsPriceAndHero() {
        let display = LimitOrderPlacementPresentation.display(
            for: makePlacementPayload(
                // 7250 blocks is not a multiple of 600.
                memo: "=<:ETH.ETH:0x1234567890abcdef1234567890abcdef12345678:16e8/7250/0:vi:50",
                coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                toAmount: 100_000_000
            )
        )

        XCTAssertNil(display?.expiryValue)
        XCTAssertEqual(display?.targetPriceValue, "1 BTC = 16 ETH")
        guard case .swap? = display?.hero else {
            return XCTFail("the hero and price must survive an unstatable expiry")
        }
    }

    /// A LIM with an astronomically large exponent must never trigger a
    /// multi-gigabyte `BigInt.power` — it decodes to `nil` and the display is
    /// rejected.
    func testAnOversizedLimExponentIsRejected() {
        XCTAssertNil(decodeCompressedLim("16e100"))
        XCTAssertNil(
            LimitOrderPlacementPresentation.display(
                for: makePlacementPayload(
                    memo: "=<:ETH.ETH:0xabc:16e100/7200/0:vi:50",
                    coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                    toAmount: 100_000_000
                )
            )
        )
    }

    /// A LIM too large to represent as a `Decimal` must not render a false zero
    /// minimum / zero price — the whole display is rejected so the co-signer
    /// falls back to the generic hero.
    func testALimBeyondDecimalRangeIsRejected() {
        let hugeLim = String(repeating: "9", count: 120)
        XCTAssertNil(
            LimitOrderPlacementPresentation.display(
                for: makePlacementPayload(
                    memo: "=<:ETH.ETH:0xabc:\(hugeLim)/7200/0:vi:50",
                    coin: makeCoin(chain: .bitcoin, ticker: "BTC", logo: "btc", decimals: 8),
                    toAmount: 100_000_000
                )
            )
        )
    }

    // MARK: - Memo parsing primitives

    func testDecodeCompressedLimHandlesBothForms() {
        XCTAssertEqual(decodeCompressedLim("1600000000"), BigInt(1_600_000_000))
        XCTAssertEqual(decodeCompressedLim("16e8"), BigInt(1_600_000_000))
        XCTAssertEqual(decodeCompressedLim("625e4"), BigInt(6_250_000))
        XCTAssertNil(decodeCompressedLim(""))
        XCTAssertNil(decodeCompressedLim("16e-8"))
        XCTAssertNil(decodeCompressedLim("nonsense"))
    }

    func testThorchainMemoAssetTickerExtraction() {
        XCTAssertEqual(thorchainMemoAssetTicker("ETH.ETH"), "ETH")
        XCTAssertEqual(thorchainMemoAssetTicker("THOR.RUNE"), "RUNE")
        XCTAssertEqual(thorchainMemoAssetTicker("ETH.USDC-06EB48"), "USDC")
        XCTAssertEqual(thorchainMemoAssetTicker("eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"), "USDC")
        XCTAssertEqual(thorchainMemoAssetTicker("btc-btc"), "BTC")
    }

    // MARK: - Helpers

    private func makeCoin(
        chain: Chain,
        ticker: String,
        logo: String,
        decimals: Int,
        contract: String = "",
        isNative: Bool = true
    ) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: logo,
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "sender", hexPublicKey: "HexPublicKeyExample")
    }

    private func makePlacementPayload(memo: String?, coin: Coin, toAmount: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "inbound",
            toAmount: toAmount,
            chainSpecific: .THORChain(
                accountNumber: 1,
                sequence: 1,
                fee: 0,
                isDeposit: false,
                transactionType: 0
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
