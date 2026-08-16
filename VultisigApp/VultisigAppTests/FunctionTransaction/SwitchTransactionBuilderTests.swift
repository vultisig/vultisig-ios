//
//  SwitchTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the Cosmos Hub → THORChain SWITCH transaction. Unlike the memo-only
//  node operations, this one carries a real transfer: the memo names who gets
//  credited, and the attached amount and destination are what actually moves.
//
//  Carries over the golden fixtures from the deleted `FunctionCallCosmosSwitchTests`
//  and `testTheSwitchParity`, which captured the legacy sub-model verbatim.
//

@testable import VultisigApp
import XCTest

final class SwitchTransactionBuilderTests: XCTestCase {

    private static let thorTarget = "thor1switchtarget"
    private static let inbound = "cosmos1inbound"

    private static func makeBuilder(
        coin: Coin = FunctionActionFixture.makeATOM(),
        thorchainAddress: String = thorTarget,
        inboundAddress: String = inbound,
        amount: Decimal = 1
    ) -> SwitchTransactionBuilder {
        SwitchTransactionBuilder(
            coin: coin,
            thorchainAddress: thorchainAddress,
            inboundAddress: inboundAddress,
            switchAmount: amount
        )
    }

    // MARK: - Memo (golden fixture)

    /// Pin: legacy `toString()` returned `SWITCH:<thorAddress>`, with no amount
    /// and no source address in it.
    func testMemoMatchesTheLegacyFormat() {
        XCTAssertEqual(Self.makeBuilder().memo, "SWITCH:\(Self.thorTarget)")
    }

    /// The THORChain address is the memo's only argument, and it rides verbatim
    /// — no casing change, no truncation. The protocol credits exactly what is
    /// written here.
    func testMemoCarriesTheAddressVerbatim() {
        let address = FunctionActionFixture.thorAddress
        XCTAssertEqual(
            Self.makeBuilder(thorchainAddress: address).memo,
            "SWITCH:\(address)"
        )
    }

    /// The amount is not in the memo — it is the transfer itself.
    func testTheAmountIsNotEncodedInTheMemo() {
        let memo = Self.makeBuilder(amount: Decimal(string: "2.5") ?? .zero).memo
        XCTAssertEqual(memo, "SWITCH:\(Self.thorTarget)")
        XCTAssertFalse(memo.contains("2.5"))
    }

    // MARK: - Attached amount (fund safety)

    /// Pin: legacy attached `amount.formatToDecimal(digits: coin.decimals)`.
    /// `SendTransaction.amountInRaw` reads this string back and scales it by
    /// `10^decimals`, so it is the exact number of ATOM that leaves the wallet.
    func testAttachedAmountMatchesTheLegacyEncoding() {
        let atom = FunctionActionFixture.makeATOM()
        for value in ["1", "1.5", "0.000001", "12345.678901"] {
            guard let amount = Decimal(string: value) else {
                return XCTFail("Bad fixture \(value)")
            }
            XCTAssertEqual(
                Self.makeBuilder(coin: atom, amount: amount).amount,
                amount.formatToDecimal(digits: atom.decimals),
                "\(value) must be attached exactly as the legacy sub-model attached it"
            )
        }
    }

    /// The amount is scaled by the SOURCE coin's decimals, not THORChain's.
    /// ATOM is six-decimal; reading it at eight would send a hundredth of what
    /// the user asked for.
    func testAttachedAmountUsesTheSourceCoinsScale() {
        let atom = FunctionActionFixture.makeATOM()
        XCTAssertEqual(atom.decimals, 6)
        let builder = Self.makeBuilder(coin: atom, amount: Decimal(string: "1.12345678") ?? .zero)
        XCTAssertEqual(builder.amount, Decimal(string: "1.123456")?.formatToDecimal(digits: 6))
    }

    /// SWITCH never sends the whole balance implicitly — the fee comes out of
    /// the same native asset, so a max-flagged transfer could not be signed.
    func testDoesNotSendMax() {
        XCTAssertFalse(Self.makeBuilder().sendMaxAmount)
    }

    // MARK: - Destination

    /// The destination is THORChain's inbound vault and nothing else: a SWITCH
    /// is an ordinary transfer whose memo is only honoured because the
    /// recipient is the vault.
    func testDestinationIsTheResolvedInboundVault() {
        let builder = Self.makeBuilder(inboundAddress: "cosmos1freshvault")
        XCTAssertEqual(builder.toAddress, "cosmos1freshvault")
        XCTAssertEqual(builder.inboundAddress, "cosmos1freshvault")
    }

    // MARK: - Memo dictionary (golden fixture)

    /// Pin: legacy `toDictionary()` wrote exactly these three keys.
    func testMemoDictionaryMatchesTheLegacyKeys() {
        let dict = Self.makeBuilder().memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["destinationAddress"], Self.inbound)
        XCTAssertEqual(dict["thorchainAddress"], Self.thorTarget)
        XCTAssertEqual(dict["memo"], "SWITCH:\(Self.thorTarget)")
        XCTAssertEqual(dict.count, 3)
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the legacy boundary (`FunctionCallCosmosSwitch.toSendTransaction`
    /// and `testTheSwitchParity`) routed to the inbound address with
    /// `.unspecified`, the memo above and the formatted amount.
    func testSendTransactionMatchesTheLegacyBoundary() {
        let atom = FunctionActionFixture.makeATOM()
        let vault = FunctionActionFixture.makeVault(coins: [atom, FunctionActionFixture.makeRUNE()])
        let builder = Self.makeBuilder(coin: atom, amount: 1)

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "SWITCH:\(Self.thorTarget)")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.toAddress, Self.inbound)
        XCTAssertEqual(tx.coin.ticker, "ATOM")
        XCTAssertEqual(tx.fromAddress, atom.address)
        XCTAssertEqual(tx.amount, Decimal(1).formatToDecimal(digits: atom.decimals))
        XCTAssertFalse(tx.sendMaxAmount)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertEqual(tx.memoFunctionDictionary["destinationAddress"], Self.inbound)
        XCTAssertEqual(tx.memoFunctionDictionary["thorchainAddress"], Self.thorTarget)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "SWITCH:\(Self.thorTarget)")
        // Builders never take gas; `FunctionTransactionScreen.onVerify` fetches
        // it before the verify screen. The legacy sub-model took it as a
        // parameter.
        XCTAssertEqual(tx.gas, .zero)
    }

    /// SWITCH is not a staking operation and carries no staking payload — the
    /// `FunctionTransactionScreen` fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = Self.makeBuilder()
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }
}
