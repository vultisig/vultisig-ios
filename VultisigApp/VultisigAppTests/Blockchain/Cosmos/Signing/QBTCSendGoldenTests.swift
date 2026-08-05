//
//  QBTCSendGoldenTests.swift
//  VultisigAppTests
//
//  Golden-vector pin for QBTC's plain MsgSend path (`transactionType` 0 /
//  `.unspecified`, the default). `QBTCHelper` signs with ML-DSA
//  (`DilithiumKeysignResponse`), not the `TssKeysignResponse` the
//  `SigningGolden*` harness's vectors are typed on, so a plain send is pinned
//  here instead of in `SigningGoldenMatrix`. `QBTCSignDirectCosignByteEqualityTests`
//  already pins the vote/signDirect path against real Windows/SDK vectors;
//  this fills the matching gap for an ordinary send, self-signed
//  deterministically (same as every other chain's send golden — no live
//  cross-platform corroboration is claimed here).
//

@testable import VultisigApp
import XCTest

final class QBTCSendGoldenTests: XCTestCase {

    private static let fromAddress = "qbtc1lm0mwvt8pknymlrat3z2slrpz0un45ghp1cx1s"
    private static let toAddress = "qbtc13vp28kmfx3kznmukw20ev8gfk8tyyt42gcqayz"
    private static let hexPublicKey = "3a2f1e0d9c8b7a6958473625140f0e0d0c0b0a090807060504030201000102"
    // Not a real ML-DSA signature — QBTCHelper.getSignedTransaction embeds it
    // in TxRaw verbatim without verifying it, so any fixed hex pins the golden.
    private static let fakeSignatureHex = String(repeating: "ab", count: 64)

    private static func makeCoin() -> Coin {
        let meta = CoinMeta(
            chain: .qbtc, ticker: "QBTC", logo: "qbtc", decimals: 8,
            priceProviderId: "", contractAddress: "", isNativeToken: true
        )
        return Coin(asset: meta, address: fromAddress, hexPublicKey: hexPublicKey)
    }

    private static func makeSendPayload() -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(),
            toAddress: toAddress,
            toAmount: 100_000_000,
            chainSpecific: .Cosmos(accountNumber: 12_345, sequence: 2, gas: 5_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
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

    func testSendPreSignedImageHash() throws {
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: Self.makeSendPayload())
        XCTAssertEqual(hashes, ["b0719b343b503d381a5d755b4982b139d94f4747de095e92d980eeba50dcf81d"])
    }

    func testSendSignedTransactionTxRaw() throws {
        let payload = Self.makeSendPayload()
        let hashes = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        guard hashes.count == 1, let hash = hashes.first else {
            XCTFail("Expected exactly one QBTC pre-sign hash")
            return
        }
        let signatures: [String: DilithiumKeysignResponse] = [
            hash: DilithiumKeysignResponse(msg: hash, signature: Self.fakeSignatureHex)
        ]
        let result = try QBTCHelper.create().getSignedTransaction(keysignPayload: payload, signatures: signatures)
        XCTAssertEqual(result.transactionHash, "BDE643649573AA72FE6702AAF7478F85C993421528FE0236831F7761E8358CF0")
        XCTAssertEqual(
            result.rawTransaction,
            "{\"tx_bytes\":\"CpABCo0BChwvY29zbW9zLmJhbmsudjFiZXRhMS5Nc2dTZW5kEm0KK3FidGMxbG0wbXd2dDhwa255bWxyYXQzejJzbHJwejB1bjQ1Z2hwMWN4MXMSK3FidGMxM3ZwMjhrbWZ4M2t6bm11a3cyMGV2OGdmazh0eXl0NDJnY3FheXoaEQoEcWJ0YxIJMTAwMDAwMDAwEmAKSgpAChsvY29zbW9zLmNyeXB0by5tbGRzYS5QdWJLZXkSIQofOi8eDZyLemlYRzYlFA8ODQwLCgkIBwYFBAMCAQABAhIECgIIARgCEhIKDAoEcWJ0YxIENTAwMBDgpxIaQKurq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s=\",\"mode\":\"BROADCAST_MODE_SYNC\"}"
        )
    }

    func testSendPreSignedImageHashIsDeterministic() throws {
        let payload = Self.makeSendPayload()
        let first = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        let second = try QBTCHelper.create().getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(first, second)
    }
}
