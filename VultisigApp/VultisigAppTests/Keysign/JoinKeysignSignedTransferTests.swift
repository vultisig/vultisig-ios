//
//  JoinKeysignSignedTransferTests.swift
//  VultisigAppTests
//
//  Pins `JoinKeysignReviewPresentation.signedTransfer(of:)`: the co-sign review
//  shows the recipient and amount of the signed `signDirect` body, never the
//  initiator's `toAddress` / `toAmount` copy.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

final class JoinKeysignSignedTransferTests: XCTestCase {

    func testReadsRecipientAndAmountFromSignedBody() throws {
        let transfer = try XCTUnwrap(signedTransfer(coins: [("uatom", "1500000")]))
        XCTAssertEqual(transfer.recipient, "cosmos1signed")
        XCTAssertEqual(transfer.amount, Decimal(string: "1.5"))
    }

    func testIgnoresPayloadCopyOfRecipientAndAmount() throws {
        // The payload copy says something else; only the signed body counts.
        let transfer = try XCTUnwrap(signedTransfer(coins: [("uatom", "2000000")], toAddress: "cosmos1spoofed", toAmount: 1))
        XCTAssertEqual(transfer.recipient, "cosmos1signed")
        XCTAssertEqual(transfer.amount, Decimal(2))
    }

    func testRejectsDenomOtherThanPayloadCoin() {
        XCTAssertNil(signedTransfer(coins: [("uosmo", "1500000")]))
    }

    func testRejectsMultiCoinSend() {
        XCTAssertNil(signedTransfer(coins: [("uatom", "1"), ("uatom", "2")]))
    }

    func testRejectsNonTransferBody() {
        let body = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [
            CosmosStakingHelper.encodeDelegate(
                delegator: "cosmos1sender", validator: "cosmosvaloper1v", amount: "1000000", denom: "uatom"
            )
        ])
        XCTAssertNil(JoinKeysignReviewPresentation.signedTransfer(of: Self.payload(body: body)))
    }

    func testRejectsMalformedBody() {
        XCTAssertNil(JoinKeysignReviewPresentation.signedTransfer(of: Self.payload(body: Data([0xFF, 0xFF]))))
    }

    func testRejectsPayloadWithoutSignDirect() {
        XCTAssertNil(JoinKeysignReviewPresentation.signedTransfer(of: Self.payload(body: nil)))
    }

    func testNonNativeCoinMatchesContractAddressDenom() throws {
        let denom = "ibc/ABC123"
        let coin = Self.coin(isNative: false, contractAddress: denom)
        let transfer = try XCTUnwrap(signedTransfer(coins: [(denom, "5000000")], coin: coin))
        XCTAssertEqual(transfer.amount, Decimal(5))
        XCTAssertNil(signedTransfer(coins: [("uatom", "5000000")], coin: coin))
    }

    // MARK: - Helpers

    private func signedTransfer(
        coins: [(denom: String, amount: String)],
        toAddress: String = "cosmos1signed",
        toAmount: BigInt = 1,
        coin: Coin = JoinKeysignSignedTransferTests.coin()
    ) -> (recipient: String, amount: Decimal)? {
        JoinKeysignReviewPresentation.signedTransfer(
            of: Self.payload(body: Self.sendBody(coins: coins, to: "cosmos1signed"), coin: coin, toAddress: toAddress, toAmount: toAmount)
        )
    }

    private static func sendBody(coins: [(denom: String, amount: String)], to: String) -> Data {
        var message = Data()
        message.appendProtoString(fieldNumber: 1, value: "cosmos1sender")
        message.appendProtoString(fieldNumber: 2, value: to)
        for (denom, amount) in coins {
            var coin = Data()
            coin.appendProtoString(fieldNumber: 1, value: denom)
            coin.appendProtoString(fieldNumber: 2, value: amount)
            message.appendProtoBytes(fieldNumber: 3, data: coin)
        }
        var any = Data()
        any.appendProtoString(fieldNumber: 1, value: "/cosmos.bank.v1beta1.MsgSend")
        any.appendProtoBytes(fieldNumber: 2, data: message)
        return CosmosStakingHelper.buildTxBodyMulti(msgsAny: [any])
    }

    private static func coin(isNative: Bool = true, contractAddress: String = "") -> Coin {
        Coin(
            asset: CoinMeta(
                chain: .gaiaChain,
                ticker: "ATOM",
                logo: Chain.gaiaChain.logo,
                decimals: 6,
                priceProviderId: "",
                contractAddress: contractAddress,
                isNativeToken: isNative
            ),
            address: "cosmos1sender",
            hexPublicKey: "00"
        )
    }

    private static func payload(
        body: Data?,
        coin: Coin = JoinKeysignSignedTransferTests.coin(),
        toAddress: String = "cosmos1destination",
        toAmount: BigInt = 1
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Cosmos(
                accountNumber: 1, sequence: 1, gas: 1, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil
            ),
            utxos: [],
            memo: nil,
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
            signData: body.map {
                .signDirect(SignDirect(
                    bodyBytes: $0.base64EncodedString(), authInfoBytes: "", chainID: "cosmoshub-4", accountNumber: "1"
                ))
            }
        )
    }
}
