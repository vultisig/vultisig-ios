//
//  LimitOrderCancelPreparerTests.swift
//  VultisigAppTests
//
//  What a cancel is allowed to cost, and what the user is told about it before
//  signing.
//
//  These moved off the deleted confirmation screen's view model. The screen went
//  because a cancel has no editable field — it arrives from the order card with
//  its assets, amounts and memo already fixed — but everything it CHECKED and
//  everything it SAID still has to happen, now on the way to Verify and on Verify
//  itself. That is what these pin.
//

import XCTest
@testable import VultisigApp

@MainActor
final class LimitOrderCancelPreparerTests: XCTestCase {

    // MARK: - The THORChain route's fee is the whole cost

    /// The pre-flight must track the number the signer actually stamps, not a
    /// second copy of it that can drift — `thorchain.swift` hardcodes the deposit
    /// gas at signing regardless of what was fetched.
    func testFeeMatchesTheSignedDepositGas() {
        XCTAssertEqual(
            limitOrderCancelThorchainFee(decimals: 8),
            Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), 8)
        )
    }

    /// A dust balance is NOT sufficient, and the DISCLOSURE says so — asserted
    /// through the value Verify actually reads, not through the arithmetic
    /// behind it. Gating on "> 0" would send the user to a Verify screen that
    /// fails at payload construction, with nothing on screen explaining why.
    func testDustBalanceCannotAffordTheDepositFee() {
        for balance in ["0", "1", String(THORChainConstants.depositGasBaseUnits - 1)] {
            let disclosures = limitOrderCancelThorchainDisclosures(for: makeRune(balance: balance))

            XCTAssertFalse(disclosures.canAffordCancel, "balance \(balance)")
        }
    }

    /// Exactly the fee is enough — a THORChain cancel attaches no coins, so the
    /// deposit gas is the entire cost. Pinned at the exact boundary because an
    /// off-by-one here either blocks a cancel the user can pay for or waves
    /// through one they cannot.
    func testExactlyTheFeeIsAffordable() {
        let atTheFee = limitOrderCancelThorchainDisclosures(
            for: makeRune(balance: String(THORChainConstants.depositGasBaseUnits))
        )
        let justOver = limitOrderCancelThorchainDisclosures(
            for: makeRune(balance: String(THORChainConstants.depositGasBaseUnits + 1))
        )

        XCTAssertTrue(atTheFee.canAffordCancel)
        XCTAssertTrue(justOver.canAffordCancel)
    }

    /// The THORChain route attaches nothing, so it has no dust to disclose and
    /// no route-specific objection to raise — affordability is the whole story.
    func testTheThorchainRouteDisclosesNoDustAndNoObjection() {
        let disclosures = limitOrderCancelThorchainDisclosures(
            for: makeRune(balance: String(THORChainConstants.depositGasBaseUnits))
        )

        XCTAssertNil(disclosures.donatedAmount)
        XCTAssertNil(disclosures.balanceObjection)
    }

    // MARK: - Which route a source chain signs a cancel through

    /// All three THORChain variants sign a cancel the same way. Missing
    /// Chainnet/Stagenet here routed those orders into the L1 destination
    /// resolver, which throws for a chain that isn't an L1 at all — cancel
    /// blocked outright for a Stagenet- or Chainnet-funded order.
    func testAllThreeThorchainVariantsRouteNative() {
        for chain in [Chain.thorChain, .thorChainChainnet, .thorChainStagenet] {
            XCTAssertTrue(
                limitOrderCancelIsThorchainSourced(sourceChainRawValue: chain.rawValue),
                "\(chain) must sign via the native MsgDeposit route"
            )
        }
    }

    func testAnL1SourceRoutesToTheDustSend() {
        XCTAssertFalse(limitOrderCancelIsThorchainSourced(sourceChainRawValue: Chain.bitcoin.rawValue))
    }

    func testAnUnknownSourceChainDoesNotRouteNative() {
        XCTAssertFalse(limitOrderCancelIsThorchainSourced(sourceChainRawValue: "not-a-real-chain"))
    }

    // MARK: - The disclosures that moved onto Verify

    /// ⚠️ The one that must never be dropped. An L1 cancel has to attach a coin
    /// for Bifrost to observe it at all, and THORNode donates whatever arrives to
    /// the pool with no refund path — up to two whole DOGE of the user's money.
    func testTheDonatedDustIsCarriedThroughToVerify() {
        let request = makeRequest().with(disclosures: LimitOrderCancelDisclosures(
            donatedAmount: "2 DOGE",
            balanceObjection: nil,
            canAffordCancel: true
        ))

        XCTAssertEqual(request.disclosures?.donatedAmount, "2 DOGE")
    }

    /// The THORChain route donates nothing, and must not imply that it does.
    func testTheThorchainRouteDeclaresNoDonatedDust() {
        let request = makeRequest().with(disclosures: LimitOrderCancelDisclosures(
            donatedAmount: nil,
            balanceObjection: nil,
            canAffordCancel: true
        ))

        XCTAssertNil(request.disclosures?.donatedAmount)
    }

    /// The duplicate-order warning rides the request from the moment the button
    /// is tapped, and survives the hop to Verify.
    func testTheDuplicateWarningSurvivesThePrepare() {
        let plain = makeRequest(duplicates: 0)
        let colliding = makeRequest(duplicates: 1)

        XCTAssertEqual(plain.with(disclosures: makeDisclosures()).duplicateRestingOrderCount, 0)
        XCTAssertEqual(colliding.with(disclosures: makeDisclosures()).duplicateRestingOrderCount, 1)
    }

    /// ⚠️ `with(disclosures:)` is a field-by-field copy, which is the shape that
    /// invites a silently dropped field. The memo in particular IS the signed
    /// bytes — losing it would address a different order, or none.
    func testAddingDisclosuresPreservesEverythingElse() {
        let original = makeRequest(duplicates: 3)

        let prepared = original.with(disclosures: makeDisclosures())

        XCTAssertEqual(prepared.orderId, original.orderId)
        XCTAssertEqual(prepared.inboundTxHash, original.inboundTxHash)
        XCTAssertEqual(prepared.memo, original.memo)
        XCTAssertEqual(prepared.sourceAsset, original.sourceAsset)
        XCTAssertEqual(prepared.targetAsset, original.targetAsset)
        XCTAssertEqual(prepared.sourceChainRawValue, original.sourceChainRawValue)
        XCTAssertEqual(prepared.duplicateRestingOrderCount, original.duplicateRestingOrderCount)
    }

    /// Nothing is disclosed until the preparer has run: the dust and the balance
    /// verdict both need the network. A request straight off the detail sheet
    /// therefore says nothing rather than saying "all clear".
    func testAnUnpreparedRequestCarriesNoDisclosures() {
        XCTAssertNil(makeRequest().disclosures)
    }

    // MARK: - The pre-sign re-check, and what it will not claim

    /// The ordinary path: the row is there and still cancellable.
    func testARestingOrderStillInStorageIsStillEligible() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault(pubKey: "vault-pub")
        let order = try LimitOrderStorageService().persist(makeCancellableRecord(), for: vault)

        XCTAssertEqual(
            limitOrderCancelRecheck(makeRequest(orderId: order.id), pubKeyECDSA: "vault-pub"),
            .stillEligible
        )
    }

    /// ⚠️ The guard's whole purpose. The order went terminal while the screen
    /// sat open, so the cancel must be refused — a memo for a closed order still
    /// costs a fee and, on L1, donates dust.
    func testAnOrderThatWentTerminalIsReportedAsChanged() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault(pubKey: "vault-pub")
        let order = try LimitOrderStorageService().persist(makeCancellableRecord(), for: vault)
        order.statusRawValue = LimitOrderStatus.filled.rawValue

        XCTAssertEqual(
            limitOrderCancelRecheck(makeRequest(orderId: order.id), pubKeyECDSA: "vault-pub"),
            .orderChanged
        )
    }

    /// A vault that WAS read and holds no such row. Signing is permitted — a
    /// device without the row has only the original decision to go on — but the
    /// verdict is not `.stillEligible`, because nothing was actually checked.
    func testAReadableVaultWithoutTheOrderIsNotClaimedToBeVerified() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        _ = TestStore.makeVault(pubKey: "vault-pub")

        let verdict = limitOrderCancelRecheck(makeRequest(orderId: "not-in-this-vault"), pubKeyECDSA: "vault-pub")

        XCTAssertEqual(verdict, .noLocalOrder)
        XCTAssertNotEqual(verdict, .stillEligible, "nothing was verified, so nothing may be claimed")
    }

    /// ⚠️ And the branch that must never be confused with the one above: storage
    /// was readable but holds no such vault, so the check did not happen. "We
    /// could not look" is not permission to sign.
    func testAVaultTheStoreCannotProduceIsUnverifiableRatherThanEligible() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let verdict = limitOrderCancelRecheck(makeRequest(), pubKeyECDSA: "no-such-vault")

        XCTAssertEqual(verdict, .unverifiable)
        XCTAssertNotEqual(verdict, .noLocalOrder, "an absent VAULT is not an absent ORDER")
        XCTAssertNotEqual(verdict, .stillEligible)
    }

    /// ⚠️ The exact condition that produced the original bug: no model context,
    /// so `LimitOrderStorageService.vault` THROWS. The old `try?` swallowed that
    /// into "no local order", which returns eligible — the guard failing open at
    /// precisely the moment it could not do its job.
    func testAThrownStoreLookupIsUnverifiableRatherThanEligible() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        Storage.shared.modelContext = nil

        let verdict = limitOrderCancelRecheck(makeRequest(), pubKeyECDSA: "vault-pub")

        XCTAssertEqual(verdict, .unverifiable)
        XCTAssertNotEqual(verdict, .stillEligible, "a lookup that threw is not a licence to sign")
        XCTAssertNotEqual(verdict, .noLocalOrder)
    }

    // MARK: - Helpers

    /// A record whose persisted form passes `limitOrderCancelEligibility` — the
    /// exact 1e8 amounts, the source chain, and assets that carry no truncated
    /// token identifier.
    private func makeCancellableRecord() -> LimitOrderRecord {
        LimitOrderRecord(
            inboundTxHash: "ABC123",
            sourceAsset: "THOR.RUNE",
            sourceAmount: "100000000",
            sourceDecimals: 8,
            targetAsset: "BTC.BTC",
            destAddress: "bc1qdest",
            targetPrice: 1,
            expiryBlocks: 14_400,
            sourceAmount1e8: "100000000",
            tradeTarget: "15979057441",
            sourceChainRawValue: Chain.thorChain.rawValue
        )
    }

    private func makeRune(balance: String) -> Coin {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
        coin.rawBalance = balance
        return coin
    }

    private func makeRequest(duplicates: Int = 0, orderId: String = "order-1") -> LimitOrderCancelRequest {
        LimitOrderCancelRequest(
            orderId: orderId,
            inboundTxHash: "ABC123",
            memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
            sourceAsset: "THOR.RUNE",
            targetAsset: "BTC.BTC",
            sourceChainRawValue: Chain.thorChain.rawValue,
            duplicateRestingOrderCount: duplicates
        )
    }

    private func makeDisclosures() -> LimitOrderCancelDisclosures {
        LimitOrderCancelDisclosures(donatedAmount: nil, balanceObjection: nil, canAffordCancel: true)
    }
}
