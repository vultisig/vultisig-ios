//
//  HyperliquidSigningParityTests.swift
//  VultisigAppTests
//
//  Byte/digest parity for the perps Hyperliquid signing groundwork.
//  Two independent oracles:
//    - Vultisig SDK `clients/cli/src/agent/hlOrder.ts` `computeHlDigest`
//      (origin/main cc88d4976, run under node with @msgpack/msgpack 3.1.2 +
//      viem 2.55.10) for msgpack bytes, connectionId and EIP-712 digests,
//      plus viem `hashTypedData` for the user-signed actions.
//    - hyperliquid-python-sdk `tests/signing_test.py`, whose signatures are
//      anchored to the production venue, for full r/s/v with a known test key.
//  Nothing here talks to the network or to a vault.
//

import WalletCore
import XCTest
@testable import VultisigApp

final class HyperliquidSigningParityTests: XCTestCase {

    // MARK: - SDK (hlOrder.ts) vectors

    private struct L1Vector {
        let action: HLValue
        let nonce: UInt64
        let isMainnet: Bool
        let vaultAddress: String?
        let msgpack: String?
        let connectionId: String
        let digest: String
    }

    private static let gtcOrderSDKKeyOrder = HLValue.object([
        ("type", .string("order")),
        ("orders", .array([.object([
            ("a", .int(0)), ("b", .bool(true)), ("p", .string("30000.0")),
            ("r", .bool(false)), ("s", .string("0.001")),
            ("t", .object([("limit", .object([("tif", .string("Gtc"))]))]))
        ])])),
        ("grouping", .string("na"))
    ])

    private static let canonicalIocOrder = HLActions.order([
        HLOrderWire(asset: 1, isBuy: false, price: "3012.5", size: "0.25", reduceOnly: false, type: .limit(.ioc))
    ])

    private static let tpslBuilderOrder = HLActions.order(
        [
            HLOrderWire(asset: 5, isBuy: true, price: "150.25", size: "12.5", reduceOnly: false, type: .limit(.gtc)),
            HLOrderWire(asset: 5, isBuy: false, price: "170", size: "12.5", reduceOnly: true,
                        type: .trigger(isMarket: true, triggerPrice: "170", kind: .takeProfit)),
            HLOrderWire(asset: 5, isBuy: false, price: "140", size: "12.5", reduceOnly: true,
                        type: .trigger(isMarket: true, triggerPrice: "140", kind: .stopLoss))
        ],
        grouping: .normalTpsl,
        builder: HLBuilderFee(builder: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd", tenthsOfBasisPoint: 10)
    )

    private static let encoderStress = HLValue.object([
        ("type", .string(String(repeating: "x", count: 40))),
        ("big", .int(70000)), ("mid", .int(300)), ("neg", .int(-5)), ("neg2", .int(-200)),
        ("u32", .uint(4_294_967_295)), ("arr", .array([.int(1), .int(2), .int(3)])),
        ("s255", .string(String(repeating: "y", count: 255))),
        ("s300", .string(String(repeating: "z", count: 300)))
    ])

    private static let vectors: [String: L1Vector] = [
        "contract_update_leverage": L1Vector(
            action: HLActions.updateLeverage(asset: 0, isCross: true, leverage: 3), nonce: 1, isMainnet: true, vaultAddress: nil,
            msgpack: "84a474797065ae7570646174654c65766572616765a5617373657400a7697343726f7373c3a86c6576657261676503",
            connectionId: "cbe9dbc971a06e83c0824e108d08607f0af3a17294e4205446f829c4ce1d3c32",
            digest: "0c7a4f06f063a81108cc24d4b5b41a9b8f2588a671f0d2a0d9b3514f4163ee2b"),
        "contract_order_limit_gtc": L1Vector(
            action: gtcOrderSDKKeyOrder, nonce: 2, isMainnet: true, vaultAddress: nil,
            msgpack: "83a474797065a56f72646572a66f72646572739186a16100a162c3a170a733303030302e30a172c2a173a5302e303031a17481a56c696d697481a3746966a3477463a867726f7570696e67a26e61",
            connectionId: "6c938d29790e8bddbd876ccffff801db90bd459e814dddc034d743a634b39715",
            digest: "33c137ad274838c376be0bdf39fce27999736e6e587a900648ea6faa531659a7"),
        "hl_canonical_order_market_ioc": L1Vector(
            action: canonicalIocOrder, nonce: 1_731_400_000_000, isMainnet: true, vaultAddress: nil,
            msgpack: "83a474797065a56f72646572a66f72646572739186a16101a162c2a170a6333031322e35a173a4302e3235a172c2a17481a56c696d697481a3746966a3496f63a867726f7570696e67a26e61",
            connectionId: "dd4a2edc509ec449fac837d2f17e394a4bb0a78cd47badb7cb6f8ba795d88b68",
            digest: "baeb3063ef821e03d884c424dce7ccda1d8105ac8f5d3ce530cfea2e158b6bf9"),
        "hl_canonical_order_testnet": L1Vector(
            action: canonicalIocOrder, nonce: 1_731_400_000_000, isMainnet: false, vaultAddress: nil, msgpack: nil,
            connectionId: "dd4a2edc509ec449fac837d2f17e394a4bb0a78cd47badb7cb6f8ba795d88b68",
            digest: "a9acbcc888681836664d8e1a86de79de361306cb0a15061af40f94a76c16499f"),
        "with_vault_address": L1Vector(
            action: HLActions.updateLeverage(asset: 159, isCross: false, leverage: 40), nonce: 1_731_400_000_123, isMainnet: true,
            vaultAddress: "0x1234567890abcdef1234567890abcdef12345678",
            msgpack: "84a474797065ae7570646174654c65766572616765a56173736574cc9fa7697343726f7373c2a86c6576657261676528",
            connectionId: "dae0338fc6de6ffb00da7d0aead2a8f5e65bc90d29aa41dfe06d91fe63c71fb5",
            digest: "11335af51fb75f129d026cadfb969ebe6c8225bb7dd8886f03e1767fbea62176"),
        "order_tpsl_builder": L1Vector(
            action: tpslBuilderOrder, nonce: 4_294_967_296, isMainnet: true, vaultAddress: nil, msgpack: nil,
            connectionId: "8066b1f21158a2b10fe82c4de0ed6b5ee1e1855b1e37cf3ad5aba30e8f0c6b73",
            digest: "af8379ec6ed088966cdc9fd04c8e014cfadca99ae8b82bd5a8ecedcd12f1c06e"),
        "long_string_and_ints": L1Vector(
            action: encoderStress, nonce: 0, isMainnet: true, vaultAddress: nil, msgpack: nil,
            connectionId: "0bd5d111813a18cd66956f7602ee15e3c285d18e022efc6ebb19bb8960582100",
            digest: "70ba2c7d8432c6b76d3959e678b804a1293ca7c6ba2784833341b194d1e09878")
    ]

    func testL1VectorsMatchSDK() throws {
        for (name, vector) in Self.vectors {
            if let expected = vector.msgpack {
                XCTAssertEqual(try HLMsgPack.encode(vector.action).hexString, expected, "msgpack \(name)")
            }
            let connectionId = try HLActionHasher.connectionId(action: vector.action, nonce: vector.nonce, vaultAddress: vector.vaultAddress)
            XCTAssertEqual(connectionId.hexString, vector.connectionId, "connectionId \(name)")
            let typed = try HLActionHasher.l1TypedData(action: vector.action, nonce: vector.nonce, isMainnet: vector.isMainnet, vaultAddress: vector.vaultAddress)
            XCTAssertEqual(typed.digest.hexString, vector.digest, "digest \(name)")
        }
    }

    func testEncoderStressPrefixesMatchSDK() throws {
        let bytes = try HLMsgPack.encode(Self.encoderStress).hexString
        // fixmap(9), "type" -> str8(40), "big" -> uint32 70000, "mid" -> uint16 300, "neg" -> fixint -5, "neg2" -> int16 -200
        XCTAssertTrue(bytes.hasPrefix("89a474797065d928" + String(repeating: "78", count: 40) + "a3626967ce00011170a36d6964cd012ca36e6567fba46e656732d1ff38"))
        XCTAssertTrue(bytes.contains("a473333030da012c"), "str16 header for 300 chars")
        XCTAssertTrue(bytes.contains("a473323535d9ff"), "str8 header for 255 chars")
    }

    func testUserSignedVectorsMatchViem() throws {
        let agent = try HLUserSignedAction.approveAgent(
            agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", agentName: "vultisig", nonce: 1_731_400_000_000, isMainnet: true)
        XCTAssertEqual(agent.typedData.digest.hexString, "b273979488cbc3c6dc2cc3bdc6910ef90179c8297817dcaecaddc648adfaf7e5")
        let builder = try HLUserSignedAction.approveBuilderFee(
            builder: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd", maxFeeRate: "0.1%", nonce: 1_731_400_000_000, isMainnet: true)
        XCTAssertEqual(builder.typedData.digest.hexString, "a90518ac1aee12472adec6ee3f20a44aea20b101c86ee03c9ae1a5ad1db4fa63")
        XCTAssertEqual(agent.action["signatureChainId"], .string("0x66eee"))
        XCTAssertEqual(agent.action["hyperliquidChain"], .string("Mainnet"))
    }

    func testApproveAgentWithoutNameSignsEmptyNameAndOmitsKey() throws {
        let agent = try HLUserSignedAction.approveAgent(
            agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", agentName: nil, nonce: 1, isMainnet: true)
        XCTAssertNil(agent.action["agentName"])
        XCTAssertEqual(agent.typedData.fields.first { $0.name == "agentName" }?.value, .string(""))
    }

    // MARK: - Existing keysign path (CustomMessagePayload -> WalletCore) signs the same digest

    func testVaultSignerPayloadDigestMatchesForL1AndUserSigned() throws {
        let signer = VaultPerpsSigner(vaultPublicKeyECDSA: "02" + String(repeating: "11", count: 32), vaultLocalPartyID: "iphone-test")
        let requests: [PerpsSignRequest] = [
            .l1(action: Self.canonicalIocOrder, nonce: 1_731_400_000_000, isMainnet: true, vaultAddress: nil),
            .l1(action: Self.tpslBuilderOrder, nonce: 4_294_967_296, isMainnet: true, vaultAddress: nil),
            .userSigned(try HLUserSignedAction.approveAgent(
                agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", agentName: "vultisig", nonce: 1_731_400_000_000, isMainnet: true)),
            .userSigned(try HLUserSignedAction.approveBuilderFee(
                builder: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd", maxFeeRate: "0.1%", nonce: 1_731_400_000_000, isMainnet: true))
        ]
        let expected = [
            "baeb3063ef821e03d884c424dce7ccda1d8105ac8f5d3ce530cfea2e158b6bf9",
            "af8379ec6ed088966cdc9fd04c8e014cfadca99ae8b82bd5a8ecedcd12f1c06e",
            "b273979488cbc3c6dc2cc3bdc6910ef90179c8297817dcaecaddc648adfaf7e5",
            "a90518ac1aee12472adec6ee3f20a44aea20b101c86ee03c9ae1a5ad1db4fa63"
        ]
        for (request, digest) in zip(requests, expected) {
            guard case let .vaultKeysign(payload, expectedDigest) = try signer.prepare(request) else {
                return XCTFail("vault signer must defer to keysign")
            }
            XCTAssertEqual(payload.method, "eth_signTypedData_v4")
            XCTAssertEqual(payload.chain, Chain.ethereum.name)
            XCTAssertNoThrow(try payload.validateEVMSignable())
            XCTAssertEqual(expectedDigest.hexString, digest)
            // The message the existing keysign ceremony would sign: WalletCore's EIP-712 over our JSON.
            XCTAssertEqual(payload.keysignMessages, [digest])
        }
    }

    // MARK: - hyperliquid-python-sdk production vectors (known test key)

    private static let pythonTestKey = Data(hexString: "0123456789012345678901234567890123456789012345678901234567890123")!

    private func assertSignature(_ request: PerpsSignRequest, r: String, s: String, v: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let signer = LocalAgentPerpsSigner(privateKeyData: Self.pythonTestKey)
        guard case let .signed(signature, _) = try signer.prepare(request) else { return XCTFail("expected signature", file: file, line: line) }
        // eth_utils.to_hex drops leading zero nibbles.
        func strip(_ hex: String) -> String { String(hex.dropFirst(2).drop { $0 == "0" }) }
        XCTAssertEqual(strip(signature.r), strip(r), "r", file: file, line: line)
        XCTAssertEqual(strip(signature.s), strip(s), "s", file: file, line: line)
        XCTAssertEqual(signature.v, v, "v", file: file, line: line)
    }

    func testPhantomAgentMatchesProduction() throws {
        let action = HLActions.order([HLOrderWire(asset: 4, isBuy: true, price: "1670.1", size: "0.0147", reduceOnly: false, type: .limit(.ioc))])
        let connectionId = try HLActionHasher.connectionId(action: action, nonce: 1_677_777_606_040, vaultAddress: nil)
        XCTAssertEqual(connectionId.hexString, "0fcbeda5ae3c4950a548021552a4fea2226858c4453571bf3f24ba017eac2908")
    }

    func testDummyActionSignatureMatchesPythonSDK() throws {
        let action = HLValue.object([("type", .string("dummy")), ("num", .uint(100_000_000_000))])
        try assertSignature(.l1(action: action, nonce: 0, isMainnet: true, vaultAddress: nil),
                            r: "0x53749d5b30552aeb2fca34b530185976545bb22d0b3ce6f62e31be961a59298",
                            s: "0x755c40ba9bf05223521753995abb2f73ab3229be8ec921f350cb447e384d8ed8", v: 27)
        try assertSignature(.l1(action: action, nonce: 0, isMainnet: false, vaultAddress: nil),
                            r: "0x542af61ef1f429707e3c76c5293c80d01f74ef853e34b76efffcb57e574f9510",
                            s: "0x17b8b32f086e8cdede991f1e2c529f5dd5297cbe8128500e00cbaf766204a613", v: 28)
        try assertSignature(.l1(action: action, nonce: 0, isMainnet: true, vaultAddress: "0x1719884eb866cb12b2287399b15f7db5e7d775ea"),
                            r: "0x3c548db75e479f8012acf3000ca3a6b05606bc2ec0c29c50c515066a326239",
                            s: "0x4d402be7396ce74fbba3795769cda45aec00dc3125a984f2a9f23177b190da2c", v: 28)
    }

    func testOrderSignaturesMatchPythonSDK() throws {
        let gtc = HLActions.order([HLOrderWire(asset: 1, isBuy: true, price: "100", size: "100", reduceOnly: false, type: .limit(.gtc))])
        try assertSignature(.l1(action: gtc, nonce: 0, isMainnet: true, vaultAddress: nil),
                            r: "0xd65369825a9df5d80099e513cce430311d7d26ddf477f5b3a33d2806b100d78e",
                            s: "0x2b54116ff64054968aa237c20ca9ff68000f977c93289157748a3162b6ea940e", v: 28)
        var withCloid = HLOrderWire(asset: 1, isBuy: true, price: "100", size: "100", reduceOnly: false, type: .limit(.gtc))
        withCloid.clientOrderId = "0x00000000000000000000000000000001"
        try assertSignature(.l1(action: HLActions.order([withCloid]), nonce: 0, isMainnet: true, vaultAddress: nil),
                            r: "0x41ae18e8239a56cacbc5dad94d45d0b747e5da11ad564077fcac71277a946e3",
                            s: "0x3c61f667e747404fe7eea8f90ab0e76cc12ce60270438b2058324681a00116da", v: 27)
        let stop = HLActions.order([HLOrderWire(asset: 1, isBuy: true, price: "100", size: "100", reduceOnly: false,
                                                type: .trigger(isMarket: true, triggerPrice: "103", kind: .stopLoss))])
        try assertSignature(.l1(action: stop, nonce: 0, isMainnet: true, vaultAddress: nil),
                            r: "0x98343f2b5ae8e26bb2587daad3863bc70d8792b09af1841b6fdd530a2065a3f9",
                            s: "0x6b5bb6bb0633b710aa22b721dd9dee6d083646a5f8e581a20b545be6c1feb405", v: 27)
    }

    func testUserSignedDomainMatchesPythonSDKUsdSend() throws {
        // sign_usd_transfer_action, testnet, signatureChainId 0x66eee.
        let typed = HLTypedData(
            domain: .userSigned(signatureChainId: 0x66eee),
            primaryType: "HyperliquidTransaction:UsdSend",
            fields: [
                HLTypedField(name: "hyperliquidChain", value: .string("Testnet")),
                HLTypedField(name: "destination", value: .string("0x5e9ee1089755c3435139848e47e6635505d5a13a")),
                HLTypedField(name: "amount", value: .string("1")),
                HLTypedField(name: "time", value: .uint64(1_687_816_341_423))
            ]
        )
        let key = try XCTUnwrap(PrivateKey(data: Self.pythonTestKey))
        let raw = try XCTUnwrap(key.sign(digest: typed.digest, curve: .secp256k1))
        let signature = try XCTUnwrap(HLSignature(recoverable: raw))
        XCTAssertEqual(signature.r, "0x637b37dd731507cdd24f46532ca8ba6eec616952c56218baeff04144e4a77073")
        XCTAssertEqual(signature.s, "0x11a6a24900e6e314136d2592e2f8d502cd89b7c15b198e1bee043c9589f9fad7")
        XCTAssertEqual(signature.v, 27)
        XCTAssertEqual(EthereumAbi.encodeTyped(messageJson: typed.signTypedDataV4JSON), typed.digest)
    }

    func testAgentSignerRefusesUserSignedActions() throws {
        let signer = LocalAgentPerpsSigner(privateKeyData: Self.pythonTestKey)
        let approve = try HLUserSignedAction.approveAgent(
            agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", agentName: nil, nonce: 1, isMainnet: true)
        XCTAssertThrowsError(try signer.prepare(.userSigned(approve))) { error in
            XCTAssertEqual(error as? PerpsSignerError, .agentCannotSignUserAction)
        }
    }

    func testAgentSignatureRecoversToAgentAddress() throws {
        let signer = LocalAgentPerpsSigner(privateKeyData: Self.pythonTestKey)
        let request = PerpsSignRequest.l1(action: Self.canonicalIocOrder, nonce: 1, isMainnet: true, vaultAddress: nil)
        guard case let .signed(signature, digest) = try signer.prepare(request) else { return XCTFail("expected signature") }
        var raw = try XCTUnwrap(Data(hexString: String(signature.r.dropFirst(2))))
        raw.append(try XCTUnwrap(Data(hexString: String(signature.s.dropFirst(2)))))
        raw.append(UInt8(signature.v - 27))
        let recovered = try XCTUnwrap(PublicKey.recover(signature: raw, message: digest))
        let address = AnyAddress(publicKey: recovered, coin: .ethereum).description.lowercased()
        XCTAssertEqual(address, signer.address)
    }

    func testInvalidVaultAddressIsRejected() {
        XCTAssertThrowsError(try HLActionHasher.connectionId(action: .null, nonce: 0, vaultAddress: "0x1234"))
    }
}
