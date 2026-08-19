//
//  ProjectionTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class ProjectionTests: XCTestCase {
    func testWholePositionUnstakeKeepsScopeWithoutEstimate() throws {
        let decoded = DecodedTransaction(operation: .unstake, amount: .unstated, evidence: .signedData)
        let hero = try XCTUnwrap(ProjectionCoordinator.hero(for: decoded, title: "You’re unstaking"))
        guard case .projected(let title, let estimate, let scope) = hero else {
            return XCTFail("expected projected hero")
        }
        XCTAssertEqual(title, "You’re unstaking")
        XCTAssertNil(estimate)
        XCTAssertEqual(scope, "scopeYourWholeStake".localized)
    }

    func testDecodedHeroStatesProjectionScopeBeforeAnyRead() throws {
        let decoded = DecodedTransaction(operation: .unstake, amount: .unstated, evidence: .signedData)
        let coin = Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "RUNE", logo: "rune", decimals: 8,
                priceProviderId: "thorchain", contractAddress: "", isNativeToken: true
            ),
            address: "thor1owner", hexPublicKey: "hex"
        )
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(for: decoded, coin: coin))
        guard case .projected(_, let estimate, let scope) = hero else {
            return XCTFail("the synchronous decoder hero must state the projection scope")
        }
        XCTAssertNil(estimate)
        XCTAssertEqual(scope, "scopeYourWholeStake".localized)
    }

    func testCommittedAmountIsNotProjected() {
        let decoded = DecodedTransaction(
            operation: .stake,
            amount: .units(BigInt(1), of: .chainNative),
            evidence: .memo
        )
        XCTAssertNil(ProjectionCoordinator.scope(for: decoded))
    }

    func testResolverUsesTrustedCoinAndRetainsScopeWhenReadFails() async throws {
        let coin = Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "TCY", logo: "tcy", decimals: 8,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: "thor1local", hexPublicKey: "hex"
        )
        let payload = KeysignPayload(
            coin: coin,
            toAddress: "thor1pool",
            toAmount: .zero,
            chainSpecific: .THORChain(accountNumber: 0, sequence: 0, fee: 0, isDeposit: true),
            utxos: [], memo: "tcy-:5000", swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: "pub", vaultLocalPartyID: "party", libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil, tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil, isQbtcClaim: false, skipBroadcast: false, signData: nil
        )
        let hero = await ResolvedTransactionHero.resolve(
            for: payload,
            trustedCoins: [coin],
            readers: [StubReader()]
        )
        XCTAssertNil(hero, "an unrelated reader cannot claim an undecoded transaction")
    }

    private struct StubReader: PositionReading {
        func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool {
            decoded.operation == .unstake && coin.chain == .thorChain
        }
        func amount(for _: DecodedTransaction, coin _: Coin) async -> HeroCoinAmount? {
            await Task.yield()
            return nil
        }
    }
}
