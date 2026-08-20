//
//  MayaChainTransactionDecoderTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

final class MayaChainTransactionDecoderTests: XCTestCase {

    func testSupportedMemoOperations() {
        let decoder = MayaChainTransactionDecoder()
        let cases: [(String, DecodedOperation, DecodedAmount, DecodedCounterparty?)] = [
            ("POOL+", .stake, .units(BigInt(100_000_000), of: .transactionCoin), nil),
            ("POOL-:5006", .unstake, .fraction(basisPoints: 5006, of: .transactionCoin), nil),
            ("BOND:BTC.BTC:123:maya1node", .bond, .unstated, .node("maya1node")),
            ("UNBOND:BTC.BTC:123:maya1node", .unbond, .unstated, .node("maya1node")),
            ("LEAVE:maya1node", .leave, .unstated, .node("maya1node"))
        ]

        for (memo, operation, amount, counterparty) in cases {
            let decoded = decoder.decode(Self.payload(memo: memo))
            XCTAssertEqual(decoded?.operation, operation, memo)
            XCTAssertEqual(decoded?.amount, amount, memo)
            XCTAssertEqual(decoded?.counterparty, counterparty, memo)
        }
    }

    func testMalformedOrOutrankedMemoIsRefused() {
        let decoder = MayaChainTransactionDecoder()
        XCTAssertNil(decoder.decode(Self.payload(memo: "POOL-:10001")))
        XCTAssertNil(decoder.decode(Self.payload(
            memo: "POOL+",
            approve: ERC20ApprovePayload(amount: 1, spender: "router")
        )))
    }

    private static func payload(
        memo: String,
        approve: ERC20ApprovePayload? = nil
    ) -> KeysignPayload {
        let coin = Coin(
            asset: CoinMeta(
                chain: .mayaChain,
                ticker: "CACAO",
                logo: "cacao",
                decimals: 8,
                priceProviderId: "cacao",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "maya1from",
            hexPublicKey: "00"
        )
        return KeysignPayload(
            coin: coin,
            toAddress: "maya1dest",
            toAmount: BigInt(100_000_000),
            chainSpecific: .MayaChain(accountNumber: 0, sequence: 0, isDeposit: true),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: approve,
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
}
