//
//  ResolvedTransactionHeroTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class ResolvedTransactionHeroTests: XCTestCase {

    private struct StubReader: PositionReading {
        let answers: Bool
        let value: HeroCoinAmount?
        func handles(_: DecodedTransaction, coin _: Coin) -> Bool { answers }
        func amount(for _: DecodedTransaction, coin _: Coin) -> HeroCoinAmount? { value }
    }

    private static func tcy(address: String = "thor1me", ticker: String = "TCY") -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: ticker, logo: "tcy", decimals: 8,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: address, hexPublicKey: "hex"
        )
    }

    private static func tcyUnstakePayload(coin: Coin = tcy()) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "thor1dest",
            toAmount: .zero,
            chainSpecific: .THORChain(accountNumber: 0, sequence: 0, fee: 0, isDeposit: true),
            utxos: [],
            memo: "tcy-:5006",
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

    /// A reader that answers enriches the projection without making its estimate
    /// look like an amount committed by the transaction.
    func testResolvesToAProjectedHeroWhenAReaderAnswers() async {
        let hero = await ResolvedTransactionHero.resolve(
            for: Self.tcyUnstakePayload(),
            trustedCoins: [Self.tcy()],
            readers: [StubReader(answers: true, value: HeroCoinAmount(amount: "1,002.571644", ticker: "TCY", logo: "tcy"))]
        )
        guard case .projected(let title, let estimate, let scope) = hero else {
            return XCTFail("expected a projected hero, got \(String(describing: hero))")
        }
        XCTAssertEqual(estimate?.amount, "1,002.571644")
        XCTAssertFalse(title.isEmpty, "the verb should be the operation's own")
        XCTAssertFalse(scope.isEmpty, "the signed fraction should remain visible")
    }

    func testFailedReadStillReturnsTheCommittedScope() async {
        let hero = await ResolvedTransactionHero.resolve(
            for: Self.tcyUnstakePayload(),
            trustedCoins: [Self.tcy()],
            readers: [StubReader(answers: true, value: nil)]
        )
        guard case .projected(_, let estimate, let scope) = hero else {
            return XCTFail("expected the projection scope without an estimate")
        }
        XCTAssertNil(estimate)
        XCTAssertFalse(scope.isEmpty)
    }

    /// Nothing reading it leaves the decoded verb-only hero to describe it.
    func testNilWhenNoReaderAnswers() async {
        let hero = await ResolvedTransactionHero.resolve(
            for: Self.tcyUnstakePayload(), trustedCoins: [Self.tcy()], readers: []
        )
        XCTAssertNil(hero)
    }

    func testUsesTheLocalVaultCoinInsteadOfPeerMetadata() async {
        let local = Self.tcy(address: "thor1local")
        let peer = Self.tcy(address: "thor1peer", ticker: "FAKE")
        let reader = TcyStakedPositionReader(readRaw: { address in
            XCTAssertEqual(address, local.address)
            return Decimal(100_000_000)
        })

        let hero = await ResolvedTransactionHero.resolve(
            for: Self.tcyUnstakePayload(coin: peer),
            trustedCoins: [local],
            readers: [reader]
        )
        guard case .projected(_, let estimate, _) = hero else {
            return XCTFail("expected a trusted TCY projection")
        }
        XCTAssertEqual(estimate?.ticker, "TCY")
    }

    /// The TCY reader gates on chain and on the amount being a fraction — an
    /// absolute amount is already in the signed content and needs no read.
    func testTcyReaderGatesOnFractionAndChain() {
        let reader = TcyStakedPositionReader()
        let fraction = DecodedTransaction(
            operation: .unstake, amount: .fraction(basisPoints: 5006, of: .transactionCoin), evidence: .memo
        )
        XCTAssertTrue(reader.handles(fraction, coin: Self.tcy()))

        let absolute = DecodedTransaction(
            operation: .unstake, amount: .units(BigInt(1), of: .transactionCoin), evidence: .memo
        )
        XCTAssertFalse(reader.handles(absolute, coin: Self.tcy()))

        let liquidityRemoval = DecodedTransaction(
            operation: .removeLiquidity,
            amount: .fraction(basisPoints: 5006, of: .transactionCoin),
            evidence: .memo
        )
        XCTAssertFalse(reader.handles(liquidityRemoval, coin: Self.tcy()))
        XCTAssertFalse(reader.handles(fraction, coin: Self.tcy(ticker: "RUNE")))
    }
}
