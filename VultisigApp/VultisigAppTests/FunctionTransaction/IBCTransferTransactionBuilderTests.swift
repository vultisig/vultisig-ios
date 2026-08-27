//
//  IBCTransferTransactionBuilderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class IBCTransferTransactionBuilderTests: XCTestCase {
    private func gaiaDestination() -> IBCDestination {
        guard let destination = IBCDestinationCatalog
            .destinations(for: FunctionActionFixture.makeOSMO())
            .first(where: { $0.chain == .gaiaChain }) else {
            fatalError("Osmosis must route to Gaia")
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
            coin: coin ?? FunctionActionFixture.makeOSMO(),
            destination: destination ?? gaiaDestination(),
            destinationAddress: FunctionActionFixture.cosmosAddress,
            userMemo: userMemo,
            amount: amount
        )
    }

    func testMemoMatchesTheLegacyShapeWithoutAUserMemo() {
        let builder = makeBuilder()

        XCTAssertEqual(
            builder.memo,
            "\(Chain.gaiaChain.name):channel-0:\(FunctionActionFixture.cosmosAddress)"
        )
        XCTAssertFalse(builder.memo.hasSuffix(":"))
    }

    func testUserMemoWithColonsRoundTripsThroughTheWireFormat() {
        let builder = makeBuilder(userMemo: "deposit:12345")
        let decoded = CosmosIBCTransferMemo(packed: builder.memo)

        XCTAssertEqual(decoded?.userMemo, "deposit:12345")
        XCTAssertEqual(decoded?.sourceChannel, "channel-0")
        XCTAssertEqual(decoded?.destinationAddress, FunctionActionFixture.cosmosAddress)
    }

    func testEveryOfferingChainProducesItsOwnChannel() {
        let expected: [(coin: Coin, destination: Chain, channel: String)] = [
            (FunctionActionFixture.makeOSMO(), .gaiaChain, "channel-0"),
            (FunctionActionFixture.makeATOM(), .osmosis, "channel-141")
        ]

        for row in expected {
            let destination = IBCDestinationCatalog.destinations(for: row.coin)
                .first(where: { $0.chain == row.destination })
            XCTAssertEqual(destination?.sourceChannel, row.channel)
        }
    }

    func testBuildSendTransactionMatchesTheLegacyBoundary() throws {
        let osmo = FunctionActionFixture.makeOSMO()
        let vault = FunctionActionFixture.makeVault(coins: [osmo])
        let builder = makeBuilder(coin: osmo, userMemo: "tag:1", amount: "1.5")

        let transaction = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(transaction.transactionType, .ibcTransfer)
        XCTAssertEqual(transaction.toAddress, FunctionActionFixture.cosmosAddress)
        XCTAssertEqual(transaction.amount, "1.5")
        XCTAssertEqual(transaction.memo, builder.memo)
        XCTAssertEqual(transaction.memoFunctionDictionary.count, 4)
        XCTAssertFalse(transaction.sendMaxAmount)
        XCTAssertFalse(transaction.isStakingOperation)
        XCTAssertNil(transaction.wasmContractPayload)
    }

    func testAttachedAmountScalesToBaseUnitsAtTheCoinsDecimals() {
        let osmo = FunctionActionFixture.makeOSMO()
        let vault = FunctionActionFixture.makeVault(coins: [osmo])

        let transaction = makeBuilder(coin: osmo, amount: "1.5").buildSendTransaction(vault: vault)

        XCTAssertEqual(transaction.amountInRaw.description, "1500000")
    }
}
