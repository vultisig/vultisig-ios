//
//  IBCTransferTransactionBuilderTests.swift
//  VultisigAppTests
//
//  The producer half of the IBC wire format, plus the `SendTransaction`
//  boundary. Every assertion the deleted `FunctionCallCosmosIBCTests` made about
//  the memo shape, the memo dictionary, the transaction type and the destination
//  address lives here — pinned to exact strings rather than to prefixes and
//  suffixes, because this string is what the signer parses.
//

@testable import VultisigApp
import XCTest

final class IBCTransferTransactionBuilderTests: XCTestCase {

    private func gaiaDestination() -> IBCDestination {
        guard let destination = IBCDestinationCatalog
            .destinations(for: FunctionCallFixture.makeKUJI())
            .first(where: { $0.chain == .gaiaChain }) else {
            fatalError("Kujira must route to Gaia")
        }
        return destination
    }

    private func makeBuilder(
        coin: Coin? = nil,
        destination: IBCDestination? = nil,
        userMemo: String = .empty,
        amount: String = "1.5"
    ) -> IBCTransferTransactionBuilder {
        IBCTransferTransactionBuilder(
            coin: coin ?? FunctionCallFixture.makeKUJI(),
            destination: destination ?? gaiaDestination(),
            destinationAddress: FunctionCallFixture.cosmosAddress,
            userMemo: userMemo,
            amount: amount
        )
    }

    // MARK: - The memo

    /// The legacy shape, pinned exactly:
    /// `<destChain.name>:<channel>:<destAddress>` with no trailing separator
    /// when the user wrote no memo.
    func testMemoMatchesTheLegacyShapeWithoutAUserMemo() {
        let builder = makeBuilder()
        XCTAssertEqual(
            builder.memo,
            "\(Chain.gaiaChain.name):channel-0:\(FunctionCallFixture.cosmosAddress)"
        )
        XCTAssertFalse(builder.memo.hasSuffix(":"))
    }

    func testMemoAppendsTheUserMemoAsAFourthSegment() {
        XCTAssertEqual(
            makeBuilder(userMemo: "hello-ibc").memo,
            "\(Chain.gaiaChain.name):channel-0:\(FunctionCallFixture.cosmosAddress):hello-ibc"
        )
    }

    /// The producer side of the fix. A memo with colons is emitted whole; the
    /// signer's bounded decode is what recovers it.
    func testAUserMemoWithColonsRoundTripsThroughTheWireFormat() {
        let payloads = [
            "deposit:12345",
            "a:b:c:d",
            #"{"forward":{"receiver":"osmo1abc","port":"transfer:0"}}"#
        ]

        for userMemo in payloads {
            let builder = makeBuilder(userMemo: userMemo)
            guard let decoded = CosmosIBCTransferMemo(packed: builder.memo) else {
                return XCTFail("\(userMemo) must decode")
            }
            XCTAssertEqual(decoded.userMemo, userMemo)
            XCTAssertEqual(decoded.sourceChannel, "channel-0")
            XCTAssertEqual(decoded.destinationAddress, FunctionCallFixture.cosmosAddress)
        }
    }

    /// The channel is the destination's, not a lookup redone at submit time —
    /// so the route the user picked is the route that gets signed.
    func testMemoCarriesTheChannelOfTheChosenRoute() {
        let kujiraToOsmosis = IBCDestinationCatalog
            .destinations(for: FunctionCallFixture.makeKUJI())
            .first { $0.chain == .osmosis }
        XCTAssertEqual(kujiraToOsmosis?.sourceChannel, "channel-3")

        guard let kujiraToOsmosis else { return XCTFail("Kujira must route to Osmosis") }
        XCTAssertTrue(makeBuilder(destination: kujiraToOsmosis).memo.contains(":channel-3:"))
    }

    func testEveryOfferingChainProducesItsOwnChannel() {
        let expected: [(coin: Coin, destination: Chain, channel: String)] = [
            (FunctionCallFixture.makeKUJI(), .gaiaChain, "channel-0"),
            (FunctionCallFixture.makeATOM(), .osmosis, "channel-141"),
            (FunctionCallFixture.makeATOM(), .kujira, "channel-343")
        ]

        for row in expected {
            guard let destination = IBCDestinationCatalog
                .destinations(for: row.coin)
                .first(where: { $0.chain == row.destination }) else {
                return XCTFail("\(row.coin.chain.rawValue) must route to \(row.destination.rawValue)")
            }
            XCTAssertEqual(destination.sourceChannel, row.channel)
            XCTAssertEqual(
                makeBuilder(coin: row.coin, destination: destination).memo,
                "\(row.destination.name):\(row.channel):\(FunctionCallFixture.cosmosAddress)"
            )
        }
    }

    // MARK: - The dictionary and the transaction

    func testMemoDictionaryKeepsTheLegacyKeys() {
        let dict = makeBuilder(userMemo: "tag:1").memoFunctionDictionary.allItems()
        XCTAssertEqual(dict.count, 4)
        XCTAssertEqual(dict["destinationChain"], Chain.gaiaChain.name)
        XCTAssertEqual(dict["destinationChannel"], "channel-0")
        XCTAssertEqual(dict["destinationAddress"], FunctionCallFixture.cosmosAddress)
        XCTAssertEqual(dict["memo"], makeBuilder(userMemo: "tag:1").memo)
    }

    func testBuildSendTransactionMatchesTheLegacyBoundary() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])
        let builder = makeBuilder(coin: kuji, amount: "1.5")

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.transactionType, .ibcTransfer)
        XCTAssertEqual(tx.toAddress, FunctionCallFixture.cosmosAddress)
        XCTAssertEqual(tx.amount, "1.5")
        XCTAssertEqual(tx.memo, builder.memo)
        XCTAssertEqual(tx.memoFunctionDictionary.count, 4)
        XCTAssertFalse(tx.sendMaxAmount)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
    }

    /// The attached amount is the transferred value, unlike the memo-only
    /// operations that pin it to zero — an IBC transfer really does move the
    /// coin. Pinned so the base-unit conversion downstream stays honest.
    func testAttachedAmountScalesToBaseUnitsAtTheCoinsDecimals() {
        let kuji = FunctionCallFixture.makeKUJI()
        let vault = FunctionCallFixture.makeVault(coins: [kuji])

        let tx = makeBuilder(coin: kuji, amount: "1.5").buildSendTransaction(vault: vault)
        XCTAssertEqual(tx.amountInRaw.description, "1500000", "1.5 KUJI at 6 decimals")
    }
}
