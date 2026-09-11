//
//  BittensorDestinationGuardTests.swift
//  VultisigAppTests
//
//  Pins the burn/zero-AccountId guard: the all-zero 32-byte AccountId
//  SS58-42-encodes to a checksum-valid Bittensor address with no known
//  private key, so `isBurnAddress` must catch it and `buildCallData`
//  (exercised via `getPreSignedImageHash`) must fail closed rather than
//  build a signable call to it.
//

@testable import VultisigApp
import BigInt
import XCTest

final class BittensorDestinationGuardTests: XCTestCase {

    /// The well-known Substrate burn address: SS58-42-encoding of the
    /// all-zero AccountId. Independently verified against
    /// `BittensorHelper.ss58Encode`'s own algorithm (Blake2b-512 checksum,
    /// base58, no leading-zero collapsing) rather than trusted as a fixture.
    private let burnAddress = "5C4hrfjw9DjXZTzV3MwzrrAr9P1MJhSrvWGWqi1eSuyUpnhM"
    private let normalAddress = "5DtJMgqtYZg6NyCM1KDkmgZ6nW7pKgL1fneDHQtwPjBrQuXG"

    // MARK: - Encoding sanity

    func testSS58EncodeOfZeroPubkeyProducesKnownBurnAddress() {
        let zeroPubkey = Data(repeating: 0, count: 32)
        let encoded = BittensorHelper.ss58Encode(publicKey: zeroPubkey)
        XCTAssertEqual(encoded, burnAddress)
    }

    func testIsValidAddressAcceptsTheBurnAddress() {
        // Documents the trap this guard exists for: the burn address is a
        // syntactically valid, checksum-passing Bittensor address, so
        // `isValidAddress` alone does not protect against it.
        XCTAssertTrue(BittensorHelper.isValidAddress(burnAddress))
    }

    // MARK: - isBurnAddress

    func testIsBurnAddressTrueForZeroAccountId() {
        XCTAssertTrue(BittensorHelper.isBurnAddress(burnAddress))
    }

    func testIsBurnAddressFalseForNormalAddress() {
        XCTAssertFalse(BittensorHelper.isBurnAddress(normalAddress))
    }

    func testIsBurnAddressFalseForUndecodableAddress() {
        XCTAssertFalse(BittensorHelper.isBurnAddress("not-an-ss58-address"))
    }

    // MARK: - buildCallData fail-closed guard (exercised via getPreSignedImageHash)

    func testGetPreSignedImageHashThrowsForBurnDestination() throws {
        let payload = makeKeysignPayload(toAddress: burnAddress)
        XCTAssertThrowsError(try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)) { error in
            guard case HelperError.runtimeError = error else {
                XCTFail("Expected HelperError.runtimeError, got \(error)")
                return
            }
        }
    }

    func testGetPreSignedImageHashBuildsForNormalDestination() throws {
        let payload = makeKeysignPayload(toAddress: normalAddress)
        let hashes = try BittensorHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertFalse(hashes.isEmpty)
    }

    // MARK: - Fixture

    private func makeKeysignPayload(toAddress: String) -> KeysignPayload {
        let meta = CoinMeta.make(chain: .bittensor, ticker: "TAO", decimals: 9, isNativeToken: true)
        let coin = Coin(
            asset: meta,
            address: "5Ej64CJQSZFsPK4byPVCZhNWiYeRXnELwYw4KYQBq6yfvaQ3",
            hexPublicKey: "75be85178816db3bc71a4f3e64e5c89866d8b7daae827ba9cf4ecd1ed9e645d5"
        )

        let chainSpecific = BlockChainSpecific.Polkadot(
            recentBlockHash: "0xe3b45c86765f382bf3df23251099c2eb8f253cb6f962738a559db79ba90c3c79",
            nonce: 0,
            currentBlockNumber: BigInt(5234567),
            specVersion: 260,
            transactionVersion: 5,
            genesisHash: "0xc41ec96637a215f4ea0505043f6055c8de087bf1d526b860990f340ea25d155d",
            gas: BigInt(200_000)
        )

        return KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: BigInt(1_000_000_000),
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b",
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
