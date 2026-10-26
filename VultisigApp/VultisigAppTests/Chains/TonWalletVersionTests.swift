//
//  TonWalletVersionTests.swift
//  VultisigApp
//
//  Sender-address -> wallet contract resolution, pinned to the SDK cross-encoder golden vectors.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class TonWalletVersionTests: XCTestCase {
    private let w5PublicKey = String(repeating: "aa", count: 32)
    private let w5Sender = "UQCvaZohosTA0ak9ZFMs-cvL1JrXqogqJH8sI2uO6k8clJpn"
    private let v4PublicKey = "6c756400bac0b153b421df6e199302537d12f7d4a53447004485700a958e7571"
    private let v4Sender = "UQCc9iCgP_b5RMJcFE5XD8zStfjtNHLhDWfUqC5m1SjSer95"

    private func payload(sender: String, hexPublicKey: String) -> KeysignPayload {
        let meta = CoinMeta(chain: .ton, ticker: "GRAM", logo: "gram", decimals: 9,
                            priceProviderId: "the-open-network", contractAddress: "", isNativeToken: true)
        return KeysignPayload(
            coin: Coin(asset: meta, address: sender, hexPublicKey: hexPublicKey),
            toAddress: "0:" + String(repeating: "bb", count: 32),
            toAmount: 1_500_000_000,
            chainSpecific: .Ton(sequenceNumber: 7, expireAt: 1_800_000_000, bounceable: true, sendMaxAmount: false),
            utxos: [], memo: nil, swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: "", vaultLocalPartyID: "p", libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil, tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil, isQbtcClaim: false, skipBroadcast: false, signData: nil
        )
    }

    func testW5NativeMatchesGoldenPreImage() throws {
        let keysign = payload(sender: w5Sender, hexPublicKey: w5PublicKey)
        let input = try TheOpenNetworkSigningInput(serializedBytes: TonHelper.getPreSignedInputData(keysignPayload: keysign))

        XCTAssertEqual(input.walletVersion, .walletV5R1)
        XCTAssertEqual(input.messages[0].mode, 3)
        XCTAssertEqual(try TonHelper.getPreSignedImageHash(keysignPayload: keysign),
                       ["abf94fba832a80f102ce54157614a39904f6616741584b6d9808f439963d9bfc"])
    }

    func testV4R2StaysV4R2() throws {
        let keysign = payload(sender: v4Sender, hexPublicKey: v4PublicKey)
        let input = try TheOpenNetworkSigningInput(serializedBytes: TonHelper.getPreSignedInputData(keysignPayload: keysign))

        XCTAssertEqual(input.walletVersion, .walletV4R2)
        XCTAssertEqual(input.messages[0].mode, 1)
    }

    func testForeignSenderIsRefused() {
        XCTAssertThrowsError(try TonHelper.getPreSignedInputData(keysignPayload: payload(sender: v4Sender, hexPublicKey: w5PublicKey)))
    }
}
