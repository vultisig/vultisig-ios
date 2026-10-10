//
//  JoinKeysignLiquidityReviewTests.swift
//  VultisigAppTests
//
//  The asset side of a THORChain or MayaChain LP add is a plain transfer from a
//  UTXO or EVM chain into an inbound vault; only its memo says it is a deposit.
//  A co-signer has to review it as one, with the pool and paired address beside
//  the amount, and must not review an unrelated send that merely carries a
//  memo starting `+:` as a liquidity add.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class JoinKeysignLiquidityReviewTests: XCTestCase {

    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try super.tearDownWithError()
    }

    private func payload(
        coin: Coin = FunctionActionFixture.makeBTC(),
        memo: String?,
        dapp: DAppMetadata? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "bc1qinboundvault",
            toAmount: 50_000,
            chainSpecific: .UTXO(byteFee: 10, sendMaxAmount: false),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil,
            dappMetadata: dapp
        )
    }

    func testAPairedAssetSideAddIsReviewedAsADeposit() {
        let memo = "+:BTC.BTC:\(AddLPFixture.mayaAddress)"
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: payload(memo: memo)), .function)
    }

    func testASingleSidedAddIsReviewedAsADeposit() {
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: payload(memo: "+:BTC.BTC")), .function)
    }

    /// `ADD:` is the long spelling of `+:`.
    func testTheLongAddSpellingIsReviewedAsADeposit() {
        let memo = "ADD:BTC.BTC:\(AddLPFixture.mayaAddress)"
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: payload(memo: memo)), .function)
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: payload(memo: "add:BTC.BTC")), .function)
    }

    func testAMemoThatNamesNoPoolIsAnOrdinarySend() {
        for memo in ["+:hello", "+:BTC.", "+:.BTC", "+:", "+", "hello", "ADD:nothing"] {
            XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: payload(memo: memo)), .send, memo)
        }
    }

    /// A dApp request keeps the review built for it.
    func testADappRequestWithALiquidityMemoIsNotRelabelled() {
        let dapp = DAppMetadata(name: "Dapp", url: "https://dapp.example", iconURL: "")
        let request = payload(memo: "+:BTC.BTC:\(AddLPFixture.mayaAddress)", dapp: dapp)
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: request), .send)
    }

    func testTheDepositReviewNamesThePoolAndThePairedAddress() throws {
        let memo = "+:ETH.ETH:\(AddLPFixture.mayaAddress)"
        let details = try XCTUnwrap(JoinKeysignReviewPresentation.liquidityDetails(for: payload(memo: memo)))

        XCTAssertEqual(details["pool"], "ETH.ETH")
        XCTAssertEqual(details["pairedAddress"], AddLPFixture.mayaAddress)
    }
}
