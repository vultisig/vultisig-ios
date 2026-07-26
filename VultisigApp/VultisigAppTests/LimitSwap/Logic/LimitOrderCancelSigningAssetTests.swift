//
//  LimitOrderCancelSigningAssetTests.swift
//  VultisigAppTests
//
//  Which asset a user has to hold before they can cancel a given order.
//
//  The answer is not the order's own asset — a cancel moves no tokens — and it
//  is not always RUNE. It was always RUNE while cancelling went through a
//  THORChain `MsgDeposit`, and stopped being so the moment the L1 route landed:
//  a BTC-funded order's cancel is a memo-bearing dust transfer sent from
//  Bitcoin, and telling its owner to add RUNE is advice that fixes nothing.
//

import XCTest
@testable import VultisigApp

final class LimitOrderCancelSigningAssetTests: XCTestCase {

    /// A THORChain-sourced order cancels via `MsgDeposit`, whose fee is paid in
    /// RUNE from the vault's THOR address.
    func testAThorchainSourcedOrderNeedsRune() {
        let asset = limitOrderCancelSigningAsset(for: makeDetails(sourceChain: .thorChain))

        XCTAssertEqual(asset?.ticker, "RUNE")
        XCTAssertEqual(asset?.chainName, "THORChain")
    }

    /// ⚠️ The bug this covers. An L1-sourced order's cancel never touches
    /// THORChain's fee — it is sent from the chain that funded the order, so
    /// that chain's native asset is what the vault is missing.
    func testAnL1SourcedOrderNeedsItsOwnChainsGasAsset() {
        for (chain, ticker, name) in [
            (Chain.bitcoin, "BTC", "Bitcoin"),
            (.ethereum, "ETH", "Ethereum"),
            (.dogecoin, "DOGE", "Dogecoin"),
            (.bscChain, "BNB", "BSC")
        ] {
            let asset = limitOrderCancelSigningAsset(for: makeDetails(sourceChain: chain))

            XCTAssertEqual(asset?.ticker, ticker, "\(chain.rawValue)")
            XCTAssertEqual(asset?.chainName, name, "\(chain.rawValue)")
            XCTAssertNotEqual(asset?.ticker, "RUNE", "\(chain.rawValue) must not be told to add RUNE")
        }
    }

    /// ⚠️ `Chain.ticker` is the base-denom spelling on the Cosmos chains
    /// (`UATOM`), which is right on the wire and nonsense in a sentence telling
    /// someone what to put in their wallet.
    func testACosmosSourcedOrderNamesTheAssetAUserWouldRecognize() {
        let asset = limitOrderCancelSigningAsset(for: makeDetails(sourceChain: .gaiaChain))

        XCTAssertEqual(asset?.ticker, "ATOM")
        XCTAssertNotEqual(asset?.ticker, Chain.gaiaChain.ticker, "UATOM is a denom, not a ticker")
    }

    /// No recorded source chain: nothing to name. The order is not cancellable
    /// at all in that state, and the eligibility predicate already says so for a
    /// better reason.
    func testAnOrderWithNoRecordedSourceChainNamesNothing() {
        XCTAssertNil(limitOrderCancelSigningAsset(for: makeDetails(sourceChainRawValue: nil)))
        XCTAssertNil(limitOrderCancelSigningAsset(for: makeDetails(sourceChainRawValue: "notAChain")))
    }

    // MARK: - Missing is not the same as unreadable

    /// The vault was read and holds the coin: nothing to say, button live.
    @MainActor
    func testAVaultHoldingTheSigningCoinCanSign() {
        let vault = makeVault(coins: [makeRune()])

        guard case let .available(coin) = limitOrderCancelSigningAvailability(
            for: makeDetails(sourceChain: .thorChain),
            in: vault
        ) else {
            return XCTFail("expected the RUNE it holds to resolve")
        }
        XCTAssertTrue(coin.isRune)
    }

    /// The vault was read and demonstrably lacks it. This is the ONLY case that
    /// earns "add %@ to this vault".
    @MainActor
    func testAVaultWithoutTheSigningCoinReportsItMissingByName() {
        let vault = makeVault(coins: [])

        guard case let .missing(asset) = limitOrderCancelSigningAvailability(
            for: makeDetails(sourceChain: .thorChain),
            in: vault
        ) else {
            return XCTFail("expected a named missing asset")
        }
        XCTAssertEqual(asset.ticker, "RUNE")
    }

    /// ⚠️ The defect this covers. A vault that could not be READ produces the
    /// same absent coin as one that genuinely lacks it, and the two deserve
    /// opposite messages: telling someone to add RUNE when the lookup merely
    /// failed sends them to acquire a coin they may already hold. Fail closed —
    /// say nothing prescriptive about an unknown.
    @MainActor
    func testAnUnreadableVaultIsUnknownRatherThanMissing() {
        let availability = limitOrderCancelSigningAvailability(
            for: makeDetails(sourceChain: .thorChain),
            in: nil
        )

        XCTAssertEqual(availability, .unknown)
        XCTAssertNotEqual(
            availability,
            .missing(LimitOrderCancelSigningAsset(ticker: "RUNE", chainName: "THORChain")),
            "an unread vault must never be reported as lacking a specific asset"
        )
    }

    /// An L1-sourced order needs its own chain's gas coin, and RUNE in the vault
    /// does not satisfy it.
    @MainActor
    func testRuneDoesNotSatisfyAnL1SourcedOrder() {
        let vault = makeVault(coins: [makeRune()])

        guard case let .missing(asset) = limitOrderCancelSigningAvailability(
            for: makeDetails(sourceChain: .bitcoin),
            in: vault
        ) else {
            return XCTFail("expected BTC to be reported missing")
        }
        XCTAssertEqual(asset.ticker, "BTC")
    }

    /// No recorded source chain: there is no asset to name, so nothing is
    /// claimed. The eligibility predicate already blocks the order for a better
    /// reason.
    @MainActor
    func testAnOrderWithNoSourceChainIsUnknownEvenWithAReadableVault() {
        XCTAssertEqual(
            limitOrderCancelSigningAvailability(
                for: makeDetails(sourceChainRawValue: nil),
                in: makeVault(coins: [makeRune()])
            ),
            .unknown
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeVault(coins: [Coin]) -> Vault {
        let vault = Vault(name: "test-vault")
        vault.coins = coins
        return vault
    }

    @MainActor
    private func makeRune() -> Coin {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
    }

    private func makeDetails(sourceChain: Chain) -> LimitOrderDetails {
        makeDetails(sourceChainRawValue: sourceChain.rawValue)
    }

    private func makeDetails(sourceChainRawValue: String?) -> LimitOrderDetails {
        LimitOrderDetails(
            id: "order-1",
            inboundTxHash: "HASH",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            targetPrice: 1,
            expiryBlocks: 14_400,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            status: .pending,
            minOutputOverride: nil,
            fill: .unobserved,
            expiry: nil,
            sourceChainRawValue: sourceChainRawValue
        )
    }
}
