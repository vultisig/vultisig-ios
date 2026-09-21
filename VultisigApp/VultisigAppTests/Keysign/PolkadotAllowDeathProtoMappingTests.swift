//
//  PolkadotAllowDeathProtoMappingTests.swift
//  VultisigAppTests
//
//  `PolkadotSpecific.allow_death` selects which Balances call every signer
//  encodes, so it has to survive the co-signer's decode and any re-encode of
//  the payload, and an absent field has to keep meaning keep-alive.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

final class PolkadotAllowDeathProtoMappingTests: XCTestCase {

    private static let hash32 = "0x" + String(repeating: "ab", count: 32)

    func testInboundAllowDeathTrueIsCarried() throws {
        var proto = makeProto()
        proto.allowDeath = true

        let specific = try BlockChainSpecific(proto: .polkadotSpecific(proto))

        XCTAssertTrue(try allowDeath(of: specific))
    }

    func testInboundUnsetAllowDeathDecodesFalse() throws {
        let specific = try BlockChainSpecific(proto: .polkadotSpecific(makeProto()))

        XCTAssertFalse(try allowDeath(of: specific))
    }

    func testOutboundAllowDeathTrueSurvivesReencode() throws {
        let specific = makeSpecific(allowDeath: true)

        guard case .polkadotSpecific(let proto) = specific.mapToProtobuff() else {
            return XCTFail("expected polkadotSpecific")
        }
        XCTAssertTrue(proto.allowDeath)
        XCTAssertTrue(try allowDeath(of: BlockChainSpecific(proto: .polkadotSpecific(proto))))
    }

    func testKeepAliveReencodeIsByteIdenticalToAPayloadWithoutTheField() throws {
        guard case .polkadotSpecific(let proto) = makeSpecific(allowDeath: false).mapToProtobuff() else {
            return XCTFail("expected polkadotSpecific")
        }

        var withoutField = makeProto()
        withoutField.gas = 250_000_000

        XCTAssertEqual(try proto.serializedData(), try withoutField.serializedData())
    }

    func testAllowDeathSurvivesAFullKeysignPayloadWireRoundTrip() throws {
        let coin = SigningGoldenFactory.coin(chain: .bittensor, ticker: "TAO", decimals: 9, curve: .ed25519)
        let payload = SigningGoldenFactory.payload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(.bittensor),
            toAmount: BigInt(1_000_000_000),
            chainSpecific: makeSpecific(allowDeath: true)
        )

        let wire = try payload.mapToProtobuff().serializedData()
        let decoded = try KeysignPayload(proto: VSKeysignPayload(serializedBytes: wire))

        XCTAssertTrue(try allowDeath(of: decoded.chainSpecific))
    }

    // MARK: - Helpers

    private func makeProto() -> VSPolkadotSpecific {
        var proto = VSPolkadotSpecific()
        proto.recentBlockHash = Self.hash32
        proto.nonce = 3
        proto.currentBlockNumber = "5234567"
        proto.specVersion = 260
        proto.transactionVersion = 5
        proto.genesisHash = Self.hash32
        return proto
    }

    private func makeSpecific(allowDeath: Bool) -> BlockChainSpecific {
        .Polkadot(
            recentBlockHash: Self.hash32,
            nonce: 3,
            currentBlockNumber: BigInt(5_234_567),
            specVersion: 260,
            transactionVersion: 5,
            genesisHash: Self.hash32,
            gas: BigInt(250_000_000),
            allowDeath: allowDeath
        )
    }

    private func allowDeath(of specific: BlockChainSpecific) throws -> Bool {
        guard case .Polkadot(_, _, _, _, _, _, _, let allowDeath) = specific else {
            XCTFail("expected Polkadot case")
            return false
        }
        return allowDeath
    }
}
