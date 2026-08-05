//
//  BittensorAndroidParityTests.swift
//  VultisigAppTests
//
//  CROSS-PLATFORM PARITY GATE for Bittensor's hand-rolled SCALE-encoded
//  extrinsic. Unlike `SigningGoldenMatrix`'s `bittensor_send` (which self-signs
//  with this repo's own fixed test key, so its pinned hash only guards
//  same-platform regression drift), this vector's inputs — destination
//  address, amount, nonce, block number, spec/tx version, genesis hash, block
//  hash — and its `expected_image_hash` are copied VERBATIM from
//  vultisig-android's `bittensor.json` fixture
//  (vultisig-android#5521, "Send TAO").
//
//  If iOS's `BittensorHelper` ever diverges from Kotlin's `BittensorHelper`
//  encoder — a different pallet/call index, a different `MultiAddress`
//  variant, a different mortal-era or compact-SCALE encoding — this fails,
//  which is the whole point of the gate. A pass here is genuine evidence the
//  two platforms sign byte-identical Bittensor extrinsics for the same
//  keysign payload, not just that iOS is consistent with itself.
//

import BigInt
@testable import VultisigApp
import XCTest

final class BittensorAndroidParityTests: XCTestCase {

    /// Verbatim from vultisig-android bittensor.json's "Send TAO" case.
    private enum AndroidFixture {
        static let toAddress = "5DtJMgqtYZg6NyCM1KDkmgZ6nW7pKgL1fneDHQtwPjBrQuXG"
        static let toAmount = BigInt(1_000_000_000)
        static let recentBlockHash = "e3b45c86765f382bf3df23251099c2eb8f253cb6f962738a559db79ba90c3c79"
        static let currentBlockNumber = BigInt(5_234_567)
        static let specVersion: UInt32 = 260
        static let transactionVersion: UInt32 = 5
        static let genesisHash = "c41ec96637a215f4ea0505043f6055c8de087bf1d526b860990f340ea25d155d"
        static let expectedImageHash = "0500005088e7e9faef052bbf655fe91f9a9effb421d4fd68a1597645918803d84c660c02286bee75000000000401000005000000c41ec96637a215f4ea0505043f6055c8de087bf1d526b860990f340ea25d155de3b45c86765f382bf3df23251099c2eb8f253cb6f962738a559db79ba90c3c7900"
    }

    private func makePayload() -> KeysignPayload {
        let meta = CoinMeta(
            chain: .bittensor, ticker: "TAO", logo: "tao", decimals: 9,
            priceProviderId: "bittensor", contractAddress: "", isNativeToken: true
        )
        // hexPublicKey / address aren't read by getPreSignedImageHash (only
        // toAddress is ss58-decoded into the call data's destination), but are
        // filled in with the Android fixture's own values for completeness.
        let coin = Coin(
            asset: meta,
            address: "5Ej64CJQSZFsPK4byPVCZhNWiYeRXnELwYw4KYQBq6yfvaQ3",
            hexPublicKey: "75be85178816db3bc71a4f3e64e5c89866d8b7daae827ba9cf4ecd1ed9e645d5"
        )
        return KeysignPayload(
            coin: coin,
            toAddress: AndroidFixture.toAddress,
            toAmount: AndroidFixture.toAmount,
            chainSpecific: .Polkadot(
                recentBlockHash: AndroidFixture.recentBlockHash,
                nonce: 0,
                currentBlockNumber: AndroidFixture.currentBlockNumber,
                specVersion: AndroidFixture.specVersion,
                transactionVersion: AndroidFixture.transactionVersion,
                genesisHash: AndroidFixture.genesisHash
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "test",
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

    func testPreSignedImageHashMatchesAndroidFixture() throws {
        let hashes = try BittensorHelper.getPreSignedImageHash(keysignPayload: makePayload())
        XCTAssertEqual(
            hashes, [AndroidFixture.expectedImageHash],
            "iOS BittensorHelper's SCALE-encoded extrinsic must byte-match vultisig-android's bittensor.json \"Send TAO\" fixture"
        )
    }
}
