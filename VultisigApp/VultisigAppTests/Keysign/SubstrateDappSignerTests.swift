//
//  SubstrateDappSignerTests.swift
//  VultisigAppTests
//
//  Pins the co-signer's Substrate dApp `signPayload` bytes to the extension's
//  `constructPolkadotSigningPayload` and Android's `SubstrateDappSigner`
//  vectors: one differing byte is a ceremony that signs two messages.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

final class SubstrateDappSignerTests: XCTestCase {

    private static let polkadotGenesis = "0x91b171bb158e2d3848fa23a9f1c25182fb8e20313b2c1eb49219da7a70ce90c3"
    private static let bittensorGenesis = "0x2f0555cc76fc2840a25a6ea3b9637146806f1f44b090c175ffde2a7e5ab36c03"
    private static let blockHash = "0x1f5a9d2c1b8e7f6a5d4c3b2a19087f6e5d4c3b2a19087f6e5d4c3b2a19087f6e"
    private static let alice = "d43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d"
    private static let transferMethod = "0x050300" + alice + "0700e40b5402"
    /// Signing bytes of `realistic` after the mode byte: spec, tx version, genesis, block hash.
    private static let realisticTail: String = "f84e0f00" + "1a000000" + polkadotGenesis.dropFirst(2) + blockHash.dropFirst(2)

    /// A taostats "Stake" request (`SubtensorModule.add_stake_limit`) as the extension sent it.
    private static let taostatsMemo = #"{"specVersion":"0x000001ef","transactionVersion":"0x00000002","address":"5CgmCqcFp162d82n7LDqkqtFZbTgaTXFovHbWUnQWgfZaF5E","assetId":null,"blockHash":"0x60b5f2f07fae5537f19ba6f8bed5c093c4a300d59260a9ad30c84273a648533c","blockNumber":"0x009228ce","era":"0xe400","genesisHash":"0x2f0555cc76fc2840a25a6ea3b9637146806f1f44b090c175ffde2a7e5ab36c03","metadataHash":null,"method":"0x0758bc0e6b701243978c1fe73d721c7b157943a713fca9f3c88cad7a9f7799bc6b26010080841e000000000002b259000000000000","mode":0,"nonce":"0x00000001","signedExtensions":["CheckNonZeroSender","CheckSpecVersion","CheckTxVersion","CheckGenesis","CheckMortality","CheckNonce","CheckWeight","ChargeTransactionPayment","SudoTransactionExtension","CheckShieldedTxValidity","SubtensorTransactionExtension","DrandPriority","CheckMetadataHash"],"tip":"0x00000000000000000000000000000000","version":4,"withSignedTransaction":true}"#

    // MARK: - Signing bytes

    /// Expected bytes: polkadot.js `ExtrinsicPayload.toU8a({ method: true })` on live Bittensor
    /// metadata (spec 495), which the extension's recipe also produces.
    func testTaostatsStakeMatchesTheChainsSigningPayload() throws {
        let payload = try XCTUnwrap(SubstrateSignerPayload.fromKeysign(chain: .bittensor, memo: Self.taostatsMemo))

        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(payload).hexString,
            "0758bc0e6b701243978c1fe73d721c7b157943a713fca9f3c88cad7a9f7799bc6b26010080841e000000000002b259000000000000"
                + "e400" + "04" + "00" + "00" + "ef010000" + "02000000"
                + Self.bittensorGenesis.dropFirst(2)
                + "60b5f2f07fae5537f19ba6f8bed5c093c4a300d59260a9ad30c84273a648533c" + "00"
        )
    }

    func testMortalTransferMatchesTheExtensionByteForByte() throws {
        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(realistic()).hexString,
            Self.transferMethod.dropFirst(2) + "f502" + "1d01" + "1e5a4b00" + "00" + Self.realisticTail + "00"
        )
    }

    func testBigTipTakesTheLengthPrefixedCompactMode() throws {
        let payload = realistic(["nonce": "0x00000100", "tip": "0x" + String(repeating: "0", count: 21) + "10000000000"])

        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(payload).hexString,
            Self.transferMethod.dropFirst(2) + "f502" + "0104" + "0b000000000001" + "00" + Self.realisticTail + "00"
        )
    }

    func testPayloadPast256BytesIsBlake2bHashed() throws {
        let payload = realistic(["method": "0x0700" + String(repeating: "ab", count: 300)])

        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(payload).hexString,
            "6b59d26a37914c7bd362b8dee98e2790b5643d1867cda84d5b28c093d1da634f"
        )
    }

    func testMetadataHashModeOneSignsTheHashAsSome() throws {
        let hash = String(repeating: "ab", count: 32)
        let payload = realistic(raw: #","mode":1,"metadataHash":"0x\#(hash)""#)

        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(payload).hexString,
            Self.transferMethod.dropFirst(2) + "f502" + "1d01" + "1e5a4b00" + "01" + Self.realisticTail + "01" + hash
        )
    }

    func testMissingAndDecimalTipsReadLikeTheHexTip() throws {
        let expected = try SubstrateDappSigner.signingBytes(realistic())
        XCTAssertEqual(try SubstrateDappSigner.signingBytes(realistic(["tip": "1234567"])), expected)
        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(realistic(["tip": nil])),
            try SubstrateDappSigner.signingBytes(realistic(["tip": "0x0"]))
        )
    }

    func testNumericTipReadsLikeTheStringTip() throws {
        XCTAssertEqual(
            try SubstrateDappSigner.signingBytes(realistic(["tip": nil], raw: #","tip":1234567"#)),
            try SubstrateDappSigner.signingBytes(realistic())
        )
    }

    func testMalformedFieldsAreRefused() {
        let malformed: [SubstrateSignerPayload] = [
            realistic(raw: #","mode":2"#),
            realistic(raw: #","mode":true"#),
            realistic(raw: #","mode":1"#),
            realistic(raw: #","mode":0,"metadataHash":"0x\#(String(repeating: "ab", count: 32))""#),
            realistic(raw: #","mode":1,"metadataHash":"0xabcd""#),
            realistic(["method": "0x050"]),
            realistic(["era": "0xzz"]),
            realistic(["nonce": "0x100000000"]),
            realistic(["specVersion": ""]),
            realistic(["tip": "-1"]),
            realistic(["tip": "0x1" + String(repeating: "0", count: 32)])
        ]
        for payload in malformed {
            XCTAssertThrowsError(try SubstrateDappSigner.signingBytes(payload), "\(payload)")
        }
    }

    // MARK: - Recognition

    func testOnlyAJsonObjectWithMethodAndGenesisIsTheRoute() throws {
        XCTAssertNil(try SubstrateSignerPayload.fromKeysign(chain: .polkadot, memo: "hello"))
        XCTAssertNil(try SubstrateSignerPayload.fromKeysign(chain: .polkadot, memo: #"{"method":"0x00"}"#))
        XCTAssertNil(try SubstrateSignerPayload.fromKeysign(chain: .polkadot, memo: nil))
        XCTAssertNil(try SubstrateSignerPayload.fromKeysign(chain: .ethereum, memo: Self.taostatsMemo))
    }

    func testAnotherChainsGenesisIsRefused() {
        XCTAssertThrowsError(try SubstrateSignerPayload.fromKeysign(chain: .polkadot, memo: Self.taostatsMemo))
    }

    // MARK: - Co-signer dispatch

    func testCoSignerSignsTheDappPayloadAndNeverBroadcasts() throws {
        let payload = try keysignPayload(chain: .bittensor, memo: Self.taostatsMemo)
        let dapp = try XCTUnwrap(SubstrateSignerPayload.fromMemo(Self.taostatsMemo))

        let messages = try KeysignMessageFactory(payload: payload, vaultPubKeyEdDSA: "").getKeysignMessages()

        XCTAssertEqual(messages, [try SubstrateDappSigner.signingBytes(dapp).hexString])
        XCTAssertTrue(payload.skipsBroadcast)
    }

    func testFeeIncludesTheSignedTip() throws {
        let oneTaoTip = Self.taostatsMemo.replacingOccurrences(
            of: #""tip":"0x00000000000000000000000000000000""#,
            with: #""tip":"0x0000000000000000000000003b9aca00""#
        )
        let gas = JoinKeysignGasViewModel()

        let withoutTip = gas.getCalculatedNetworkFee(payload: try keysignPayload(chain: .bittensor, memo: Self.taostatsMemo))
        let withTip = gas.getCalculatedNetworkFee(payload: try keysignPayload(chain: .bittensor, memo: oneTaoTip))

        XCTAssertTrue(withoutTip.feeCrypto.hasPrefix("0.0002"), withoutTip.feeCrypto)
        XCTAssertTrue(withTip.feeCrypto.hasPrefix("1.0002"), withTip.feeCrypto)
    }

    // MARK: - Review

    func testReviewReadsADappTransferFromTheSignedCall() throws {
        let payload = try keysignPayload(chain: .polkadot, memo: memo(Self.realisticFields))

        let transfer = try XCTUnwrap(JoinKeysignReviewPresentation.signedTransfer(of: payload))
        XCTAssertEqual(transfer.recipient, "15oF4uVJwmo4TdGW7VfQxNLavjCXviqxT9S1MgbjMNHr6Sp5")
        XCTAssertEqual(transfer.amount, Decimal(1))
        XCTAssertTrue(payload.skipsBroadcast)
    }

    func testReviewShowsNoAmountForANonTransferCall() throws {
        let payload = try keysignPayload(chain: .bittensor, memo: Self.taostatsMemo)

        XCTAssertNil(JoinKeysignReviewPresentation.signedTransfer(of: payload))
        XCTAssertEqual(JoinKeysignReviewPresentation.substrateDappReading(of: payload), .otherCall)
        XCTAssertEqual(payload.toAmount, .zero)
    }

    func testDoneAndNotificationReadTheSignedTransfer() throws {
        let transfer = try keysignPayload(chain: .polkadot, memo: memo(Self.realisticFields))

        XCTAssertEqual(
            JoinKeysignReviewPresentation.substrateDappReading(of: transfer),
            .transfer(recipient: "15oF4uVJwmo4TdGW7VfQxNLavjCXviqxT9S1MgbjMNHr6Sp5", amount: 1)
        )
    }

    // MARK: - Helpers

    /// `transfer_keep_alive(Alice, 1 DOT)`, nonce 71, tip 1_234_567, runtime 1_003_256.
    private static let realisticFields: [String: String] = [
        "address": "15oF4uVJwmo4TdGW7VfQxNLavjCXviqxT9S1MgbjMNHr6Sp5",
        "blockHash": blockHash,
        "blockNumber": "0x01312d00",
        "era": "0xf502",
        "genesisHash": polkadotGenesis,
        "method": transferMethod,
        "nonce": "0x00000047",
        "specVersion": "0x000f4ef8",
        "tip": "0x0000000000000000000000000012d687",
        "transactionVersion": "0x0000001a"
    ]

    private func memo(_ fields: [String: String], raw: String = "") -> String {
        let body = fields.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
        return "{\(body)\(raw),\"version\":4}"
    }

    private func realistic(_ overrides: [String: String?] = [:], raw: String = "") -> SubstrateSignerPayload {
        var fields = Self.realisticFields
        for (key, value) in overrides { fields[key] = value }
        guard let payload = SubstrateSignerPayload.fromMemo(memo(fields, raw: raw)) else {
            preconditionFailure("fixture is not a signer payload")
        }
        return payload
    }

    private func keysignPayload(chain: Chain, memo: String) throws -> KeysignPayload {
        var specific = VSPolkadotSpecific()
        specific.recentBlockHash = Self.blockHash
        specific.currentBlockNumber = "1"
        specific.genesisHash = chain.substrateGenesisHash ?? .empty
        specific.gas = 200_000
        let base = SigningGoldenFactory.payload(
            coin: SigningGoldenFactory.coin(chain: chain, ticker: chain.ticker, decimals: chain == .polkadot ? 10 : 9, curve: .ed25519),
            toAddress: SigningGoldenFactory.recipient(chain),
            toAmount: BigInt(1),
            chainSpecific: try BlockChainSpecific(proto: .polkadotSpecific(specific))
        )
        var proto = base.mapToProtobuff()
        proto.toAddress = ""
        proto.toAmount = ""
        proto.memo = memo
        return try KeysignPayload(proto: proto)
    }
}
