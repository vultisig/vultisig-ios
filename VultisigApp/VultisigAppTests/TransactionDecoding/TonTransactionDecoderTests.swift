//
//  TonTransactionDecoderTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class TonTransactionDecoderTests: XCTestCase {

    func testAllExactNominatorCommentsDecodeWithAColdDirectory() {
        let decoder = TonTransactionDecoder()
        XCTAssertEqual(decoder.decode(Self.payload(to: "EQtf", memo: "d"))?.operation, .stake)
        XCTAssertEqual(decoder.decode(Self.payload(to: "EQtf", memo: "w"))?.operation, .unstake)
        XCTAssertEqual(decoder.decode(Self.payload(to: "EQwhales", memo: "Deposit"))?.operation, .stake)
        XCTAssertEqual(decoder.decode(Self.payload(to: "EQwhales", memo: "Withdraw"))?.operation, .unstake)
    }

    func testDepositUsesTheExactSignedTonAmount() {
        let decoded = TonTransactionDecoder().decode(Self.payload(to: "EQpool", memo: "d"))
        XCTAssertEqual(decoded?.operation, .stake)
        XCTAssertEqual(decoded?.amount, .units(BigInt(1_000_000_000), of: .chainNative))
    }

    @MainActor
    func testDepositHeroIncludesFiat() throws {
        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "the-open-network", value: 5)
        ])
        let decoded = try XCTUnwrap(
            TonTransactionDecoder().decode(Self.payload(to: "EQpool", memo: "d"))
        )
        let hero = try XCTUnwrap(
            DecodedTransactionPresentation.hero(for: decoded, coin: Self.tonCoin)
        )

        guard case .send(_, let amount) = hero else {
            return XCTFail("expected an exact deposit amount")
        }
        XCTAssertEqual(amount.amount, "1")
        XCTAssertFalse(amount.fiat?.isEmpty ?? true)
    }

    func testWithdrawTreatsTheCarrierAsAWholePositionRequest() {
        let decoded = TonTransactionDecoder().decode(Self.payload(to: "EQpool", memo: "w"))
        XCTAssertEqual(decoded?.operation, .unstake)
        XCTAssertEqual(decoded?.amount, .unstated)
        XCTAssertEqual(decoded?.counterparty, .pool("EQpool"))
    }

    func testCommentsRemainExactAndCaseSensitive() {
        let decoder = TonTransactionDecoder()
        for memo in [" d", "d ", "D", "deposit", "withdraw", "W", "claim", "redelegate"] {
            XCTAssertNil(decoder.decode(Self.payload(to: "EQpool", memo: memo)), memo)
        }
    }

    func testTonConnectSignedDataMakesTheOuterCommentInert() {
        let payload = Self.payload(
            to: "EQpool",
            memo: "d",
            signData: .signTon(SignTon(tonMessages: []))
        )
        XCTAssertNil(TonTransactionDecoder().decode(payload))
    }

    func testWholePositionProjectionUsesTheSignedPoolAndTrustedOwner() async throws {
        try await MainActor.run {
            try RateProvider.shared.save(rates: [
                Rate(fiat: SettingsCurrency.current.rawValue, crypto: "the-open-network", value: 5)
            ])
        }
        let reader = TonStakedPositionReader(readPools: { owner in
            XCTAssertEqual(owner, "EQfrom")
            return [
                TonAccountStakingInfo(
                    pool: "EQother",
                    amount: 9_000_000_000,
                    pendingDeposit: 0,
                    pendingWithdraw: 0,
                    readyWithdraw: 0
                ),
                TonAccountStakingInfo(
                    pool: "EQpool",
                    amount: 2_000_000_000,
                    pendingDeposit: 500_000_000,
                    pendingWithdraw: 0,
                    readyWithdraw: 0
                )
            ]
        })
        let decoded = try XCTUnwrap(TonTransactionDecoder().decode(Self.payload(to: "EQpool", memo: "w")))
        let amount = await reader.amount(for: decoded, coin: Self.tonCoin)
        XCTAssertEqual(amount?.amount, "2.5")
        XCTAssertFalse(amount?.fiat?.isEmpty ?? true)
    }

    private static var tonCoin: Coin {
        Coin(
            asset: CoinMeta(
                chain: .ton,
                ticker: "TON",
                logo: "ton",
                decimals: 9,
                priceProviderId: "the-open-network",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "EQfrom",
            hexPublicKey: "00"
        )
    }

    private static func payload(
        to destination: String,
        memo: String,
        signData: SignData? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: tonCoin,
            toAddress: destination,
            toAmount: BigInt(1_000_000_000),
            chainSpecific: .Ton(sequenceNumber: 1, expireAt: 0, bounceable: true, sendMaxAmount: false),
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
            signData: signData
        )
    }
}
