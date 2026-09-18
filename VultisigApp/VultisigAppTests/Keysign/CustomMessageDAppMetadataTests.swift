//
//  CustomMessageDAppMetadataTests.swift
//  VultisigAppTests
//
//  A dApp message-signing request travels as a `CustomMessagePayload` with no
//  `KeysignPayload` beside it, so the payload itself has to carry the dApp's
//  identity. These tests pin the three properties that make that safe:
//  the field survives the wire in both transports, a payload without a dApp
//  still encodes exactly as it did before the field existed, and the identity
//  never reaches the digest co-signers on other platforms recompute.
//

@testable import VultisigApp
import CryptoSwift
import Foundation
import VultisigCommonData
import WalletCore
import XCTest

final class CustomMessageDAppMetadataTests: XCTestCase {

    /// Serialized by the commondata schema outside Swift (`buf convert`), so
    /// decoding it proves this mapping agrees with the Go and TypeScript
    /// producers rather than merely with its own encoder.
    private let crossLanguageFixtureHex = "0a0d706572736f6e616c5f7369676e120c307834383635366336633666"
        + "1a0530326162632a08457468657265756d32240a0a506f6c796d61726b6574"
        + "121668747470733a2f2f706f6c796d61726b65742e636f6d"

    /// The same message without `dapp_metadata`: the fixture minus field 6.
    private let fixtureWithoutMetadataHex = "0a0d706572736f6e616c5f7369676e120c307834383635366336633666"
        + "1a0530326162632a08457468657265756d"

    private let polymarket = DAppMetadata(name: "Polymarket", url: "https://polymarket.com", iconURL: "")

    // MARK: - Proto mapping

    func testRoundTripPreservesAllThreeFields() throws {
        let metadata = DAppMetadata(
            name: "Uniswap",
            url: "https://app.uniswap.org",
            iconURL: "https://app.uniswap.org/favicon.png"
        )
        let decoded = try CustomMessagePayload(proto: makePayload(dappMetadata: metadata).mapToProtobuff())

        XCTAssertEqual(decoded.dappMetadata, metadata)
    }

    func testAbsentFieldDecodesToNil() throws {
        let proto = makePayload().mapToProtobuff()

        XCTAssertFalse(proto.hasDappMetadata)
        XCTAssertNil(try CustomMessagePayload(proto: proto).dappMetadata)
    }

    func testWhitespaceOnlyFieldsDecodeToNil() throws {
        var proto = makePayload().mapToProtobuff()
        proto.dappMetadata = .with {
            $0.name = "  "
            $0.url = "\n"
            $0.iconURL = " \t "
        }

        XCTAssertNil(try CustomMessagePayload(proto: proto).dappMetadata)
    }

    func testPresentButEmptyMessageDecodesToNil() throws {
        var proto = makePayload().mapToProtobuff()
        proto.dappMetadata = VSDAppMetadata()

        XCTAssertTrue(proto.hasDappMetadata)
        XCTAssertNil(try CustomMessagePayload(proto: proto).dappMetadata)
    }

    func testFieldsAreTrimmedAtTheBoundary() throws {
        var proto = makePayload().mapToProtobuff()
        proto.dappMetadata = .with {
            $0.name = " Polymarket\n"
            $0.url = "  https://polymarket.com "
        }

        XCTAssertEqual(try CustomMessagePayload(proto: proto).dappMetadata, polymarket)
    }

    func testNameOnlyMetadataSurvives() throws {
        let metadata = DAppMetadata(name: "Uniswap", url: "", iconURL: "")
        let decoded = try CustomMessagePayload(proto: makePayload(dappMetadata: metadata).mapToProtobuff())

        XCTAssertEqual(decoded.dappMetadata, metadata)
    }

    func testURLOnlyMetadataSurvives() throws {
        let metadata = DAppMetadata(name: "", url: "https://app.uniswap.org", iconURL: "")
        let decoded = try CustomMessagePayload(proto: makePayload(dappMetadata: metadata).mapToProtobuff())

        XCTAssertEqual(decoded.dappMetadata, metadata)
        XCTAssertEqual(decoded.dappMetadata?.host, "app.uniswap.org")
    }

    /// Both payload kinds go through one normalisation, so a transaction and a
    /// message from the same dApp can never disagree on what counts as empty.
    func testSharedNormalisationTrimsAndDropsEmptyMetadata() {
        let whitespace = VSDAppMetadata.with {
            $0.name = " "
            $0.url = "\n"
        }
        let padded = VSDAppMetadata.with {
            $0.name = " Polymarket "
            $0.url = "https://polymarket.com\n"
        }

        XCTAssertNil(DAppMetadata(proto: whitespace))
        XCTAssertEqual(DAppMetadata(proto: padded), polymarket)
    }

    // MARK: - Wire compatibility

    func testNilMetadataEncodesToTheBytesOfAPayloadWithoutTheField() throws {
        let payload = CustomMessagePayload(
            method: "personal_sign",
            message: "0x48656c6c6f",
            vaultPublicKeyECDSA: "02abc",
            vaultLocalPartyID: "",
            chain: "Ethereum"
        )
        let withoutField = VSCustomMessagePayload.with {
            $0.method = "personal_sign"
            $0.message = "0x48656c6c6f"
            $0.vaultPublicKeyEcdsa = "02abc"
            $0.chain = "Ethereum"
        }

        let encoded = try payload.mapToProtobuff().serializedData()

        XCTAssertEqual(encoded, try withoutField.serializedData())
        XCTAssertEqual(encoded.hexString, fixtureWithoutMetadataHex)
    }

    /// Metadata that would decode to `nil` must not be written at all, or a
    /// round trip changes the value and "no dApp" stops being byte-identical.
    func testEmptyMetadataIsNotWrittenToTheWire() throws {
        let blank = DAppMetadata(name: "", url: "", iconURL: "")
        let whitespace = DAppMetadata(name: " ", url: "\n", iconURL: "\t")

        for metadata in [blank, whitespace] {
            let proto = makePayload(dappMetadata: metadata).mapToProtobuff()

            XCTAssertFalse(proto.hasDappMetadata)
            XCTAssertNil(try CustomMessagePayload(proto: proto).dappMetadata)
        }

        let encoded = try CustomMessagePayload(
            method: "personal_sign",
            message: "0x48656c6c6f",
            vaultPublicKeyECDSA: "02abc",
            vaultLocalPartyID: "",
            chain: "Ethereum",
            dappMetadata: whitespace
        ).mapToProtobuff().serializedData()
        XCTAssertEqual(encoded.hexString, fixtureWithoutMetadataHex)
    }

    func testPaddedMetadataIsWrittenTrimmed() throws {
        let padded = DAppMetadata(name: " Polymarket ", url: "https://polymarket.com\n", iconURL: "")

        let proto = makePayload(dappMetadata: padded).mapToProtobuff()

        XCTAssertEqual(proto.dappMetadata.name, "Polymarket")
        XCTAssertEqual(proto.dappMetadata.url, "https://polymarket.com")
        XCTAssertEqual(try CustomMessagePayload(proto: proto).dappMetadata, polymarket)
    }

    func testDecodesCrossLanguageFixture() throws {
        let proto = try VSCustomMessagePayload(serializedBytes: Data(hex: crossLanguageFixtureHex))
        let payload = try CustomMessagePayload(proto: proto)

        XCTAssertEqual(payload.method, "personal_sign")
        XCTAssertEqual(payload.message, "0x48656c6c6f")
        XCTAssertEqual(payload.vaultPublicKeyECDSA, "02abc")
        XCTAssertEqual(payload.vaultLocalPartyID, "")
        XCTAssertEqual(payload.chain, "Ethereum")
        XCTAssertEqual(payload.dappMetadata, polymarket)
    }

    func testEncodesToTheCrossLanguageFixtureBytes() throws {
        let payload = CustomMessagePayload(
            method: "personal_sign",
            message: "0x48656c6c6f",
            vaultPublicKeyECDSA: "02abc",
            vaultLocalPartyID: "",
            chain: "Ethereum",
            dappMetadata: polymarket
        )

        XCTAssertEqual(try payload.mapToProtobuff().serializedData().hexString, crossLanguageFixtureHex)
    }

    // MARK: - Transports

    /// A payload too large for the QR is uploaded on its own and fetched by
    /// `customPayloadID`, so the standalone message has to carry the identity.
    func testStandaloneRelayPayloadKeepsMetadata() throws {
        let serialized = try ProtoSerializer.serialize(makePayload(dappMetadata: polymarket))
        let fetched: CustomMessagePayload = try ProtoSerializer.deserialize(base64EncodedString: serialized)

        XCTAssertEqual(fetched.dappMetadata, polymarket)
    }

    func testKeysignMessageKeepsMetadataOnItsCustomMessagePayload() throws {
        let message = KeysignMessage(
            sessionID: "session",
            serviceName: "service",
            payload: nil,
            customMessagePayload: makePayload(dappMetadata: polymarket),
            encryptionKeyHex: "00",
            useVultisigRelay: true,
            payloadID: "",
            customPayloadID: ""
        )
        let serialized = try ProtoSerializer.serialize(message)
        let decoded: KeysignMessage = try ProtoSerializer.deserialize(base64EncodedString: serialized)

        XCTAssertNil(decoded.payload)
        XCTAssertEqual(decoded.customMessagePayload?.dappMetadata, polymarket)
    }

    // MARK: - Signing is untouched

    /// Expected digests are computed outside Swift, so a regression in the
    /// derivation cannot hide behind both sides of the comparison moving.
    func testKeysignMessagesIgnoreMetadata() {
        let cases: [(label: String, method: String, message: String, chain: String, expected: String)] = [
            ("personal_sign", "personal_sign", "0x48656c6c6f", "Ethereum",
             "06b3dfaec148fb1bb2b066f10ec285e7c9bf402ab32aa78a5d38e34566810cd2"),
            ("EIP-712", "eth_signTypedData_v4", Self.typedDataJSON, "Ethereum",
             "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"),
            ("Cosmos", "sign", "Hello Vultisig", "Cosmos",
             "06566f01e5e53c8d32ec7c977c242887d9d1107182c0a1cd8f6f1e4d602c346f"),
            ("Solana", "sign_message", "0xdeadbeef", "Solana", "deadbeef"),
            ("Cardano", "signTx", "0x" + String(repeating: "ab", count: 32), "Cardano",
             String(repeating: "ab", count: 32)),
            ("Ripple", "sign_message", "Hello, XRPL!", "Ripple",
             "f6805caef386076db074419d22a349341b0fa09c17838a2bdee43b2dc73cb988")
        ]

        for testCase in cases {
            let bare = makePayload(method: testCase.method, message: testCase.message, chain: testCase.chain)
            let withMetadata = makePayload(
                method: testCase.method,
                message: testCase.message,
                chain: testCase.chain,
                dappMetadata: polymarket
            )

            XCTAssertEqual(withMetadata.keysignMessages, bare.keysignMessages, testCase.label)
            XCTAssertEqual(bare.keysignMessages, [testCase.expected], testCase.label)
        }
    }

    // MARK: - Codable

    func testDecodesJSONWrittenBeforeTheFieldExisted() throws {
        let json = """
        {"method":"personal_sign","message":"0x48656c6c6f","vaultPublicKeyECDSA":"02abc",\
        "vaultLocalPartyID":"party","chain":"Ethereum"}
        """
        let decoded = try JSONDecoder().decode(CustomMessagePayload.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.method, "personal_sign")
        XCTAssertNil(decoded.dappMetadata)
    }

    func testCodableRoundTripKeepsMetadata() throws {
        let payload = makePayload(dappMetadata: polymarket)
        let decoded = try JSONDecoder().decode(
            CustomMessagePayload.self,
            from: JSONEncoder().encode(payload)
        )

        XCTAssertEqual(decoded, payload)
    }

    // MARK: - Helpers

    private func makePayload(
        method: String = "personal_sign",
        message: String = "0x48656c6c6f",
        chain: String = "Ethereum",
        dappMetadata: DAppMetadata? = nil
    ) -> CustomMessagePayload {
        CustomMessagePayload(
            method: method,
            message: message,
            vaultPublicKeyECDSA: "02abc",
            vaultLocalPartyID: "party",
            chain: chain,
            dappMetadata: dappMetadata
        )
    }

    /// The reference message from the EIP-712 specification.
    private static let typedDataJSON = """
    {"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},\
    {"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],\
    "Person":[{"name":"name","type":"string"},{"name":"wallet","type":"address"}],\
    "Mail":[{"name":"from","type":"Person"},{"name":"to","type":"Person"},{"name":"contents","type":"string"}]},\
    "primaryType":"Mail",\
    "domain":{"name":"Ether Mail","version":"1","chainId":1,\
    "verifyingContract":"0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"},\
    "message":{"from":{"name":"Cow","wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},\
    "to":{"name":"Bob","wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},"contents":"Hello, Bob!"}}
    """
}
