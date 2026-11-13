//
//  HyperliquidCoSignVerifierTests.swift
//  VultisigAppTests
//
//  The joiner-side check of a Hyperliquid keysign payload: the strict
//  msgpack decoder, digest rebuild from the raw action, the action
//  allowlist, time bounds, and the user-signed pins. Every tampered or
//  incomplete payload must be refused before anything is signed.
//

import XCTest
@testable import VultisigApp

final class HyperliquidCoSignVerifierTests: XCTestCase {
    private static let nonce: UInt64 = 1_731_400_000_000
    private static let main = "0x9d7c000000000000000000000000000000003003"
    private static let trading = "0x1185000000000000000000000000000000001185"

    private var context: HyperliquidCoSignContext {
        HyperliquidCoSignContext(mainAddress: Self.main, tradingAddress: Self.trading, nowMs: Self.nonce,
                                 coinName: { $0 == 0 ? "BTC" : nil })
    }

    private func market() -> PerpsMarket {
        PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: 66_969,
                    midPrice: 66_969, previousDayPrice: 66_000, hourlyFunding: 0, openInterest: 1, dayVolume: 1, marginTiers: [])
    }

    private func orderAction(builder: HLBuilderFee? = PerpsConfig.builderFee(tier: nil)) throws -> HLValue {
        let ticket = PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated, limitPrice: nil,
                                 takeProfit: nil, stopLoss: 62_000)
        return try PerpsOrderPlanner.orderAction(market: market(), ticket: ticket, size: Decimal(string: "0.00298") ?? 0,
                                                 price: 67_638, builder: builder)
    }

    private func payload(_ request: HLExchangeRequest) throws -> CustomMessagePayload {
        let signer = VaultPerpsSigner(vaultPublicKeyECDSA: "02aa", vaultLocalPartyID: "iPhone", account: .trading)
        guard case .vaultKeysign(let payload, let digest) = try signer.prepare(request.signRequest) else {
            XCTFail("expected a vault keysign payload")
            throw PerpsSignerError.signingFailed
        }
        XCTAssertEqual(payload.keysignMessages.first, digest.hexString)
        return payload
    }

    private func l1Payload(_ action: HLValue, kind: HLExchangeRequest.Kind = .order, expiryMs: UInt64 = 60_000,
                           vaultAddress: String? = nil) throws -> CustomMessagePayload {
        try payload(try .l1(kind, action: action, nonce: Self.nonce, isMainnet: true, vaultAddress: vaultAddress,
                            expiresAfter: Self.nonce + expiryMs))
    }

    private func assertRefused(_ payload: CustomMessagePayload, _ expected: HyperliquidCoSignRefusal,
                               context: HyperliquidCoSignContext? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try HyperliquidCoSignVerifier.verify(payload, context: context ?? self.context), file: file, line: line) {
            XCTAssertEqual($0 as? HyperliquidCoSignRefusal, expected, file: file, line: line)
        }
    }

    // MARK: - Decoder

    func testDecoderRoundTripsSDKVectors() throws {
        // hyperliquid-python-sdk `msgpack.packb` output (gen_exchange_sdk.py, gen_modify_sdk.py).
        let vectors = [
            "82a474797065a663616e63656ca763616e63656c739182a16100a16fce075bcd15",
            "84a474797065b475706461746549736f6c617465644d617267696ea5617373657405a56973427579c3a46e746c69d2fe7ae6a0",
            "81a474797065a46e6f6f70",
            "82a474797065ab62617463684d6f64696679a86d6f6469666965739182a36f69644da56f7264657286a16100a162c2a170a53632303030a173a5302e303032"
                + "a172c3a17481a77472696767657283a869734d61726b6574c3a9747269676765725078a53632303030a47470736ca2736c"
        ]
        for hex in vectors {
            let bytes = try XCTUnwrap(Data(hexString: hex))
            let value = try HLMsgPackDecoder.decodeCanonical(bytes)
            XCTAssertEqual(try HLMsgPack.encode(value), bytes)
        }
        XCTAssertEqual(try HLMsgPackDecoder.decode(try XCTUnwrap(Data(hexString: "81a474797065a46e6f6f70"))), HLActions.noop)
    }

    func testDecoderRefusesWhatTheEncoderWouldNotProduce() throws {
        func refuses(_ hex: String, _ error: HLMsgPackDecodeError, line: UInt = #line) throws {
            XCTAssertThrowsError(try HLMsgPackDecoder.decodeCanonical(try XCTUnwrap(Data(hexString: hex))), line: line) {
                XCTAssertEqual($0 as? HLMsgPackDecodeError, error, line: line)
            }
        }
        try refuses("81a474797065d9046e6f6f70", .nonCanonical)              // "noop" as str8
        try refuses("cc05", .nonCanonical)                                   // 5 as uint8
        try refuses("81a474797065a46e6f6f70c0", .trailingBytes)
        try refuses("cb3ff0000000000000", .unsupportedType(0xcb))            // float64
        try refuses("c40100", .unsupportedType(0xc4))                        // bin8
        try refuses("810101", .nonStringKey)
        try refuses("82a474797065", .truncated)
        try refuses(String(repeating: "91", count: 20) + "c0", .tooDeep)
    }

    // MARK: - L1

    func testOrderVerifiesAndRendersWhatIsSigned() throws {
        let summary = try XCTUnwrap(HyperliquidCoSignVerifier.verify(try l1Payload(try orderAction()), context: context))
        XCTAssertEqual(summary.lines.count, 4, "entry, stop loss, builder fee, network")
        XCTAssertEqual(summary.lines.last, String(format: "perpsCoSignNetwork".localized, "Mainnet"))
        XCTAssertTrue(summary.lines[0].contains("0.00298"))
        XCTAssertTrue(summary.lines[0].contains("BTC"))
        XCTAssertTrue(summary.lines[0].contains("67,638"))
        XCTAssertTrue(summary.lines[1].contains("62,000"))
        XCTAssertTrue(summary.lines[2].contains("0.1%"))
        XCTAssertEqual(summary.signingAs, "perpsTradingAccountShort".localized + " · 0x1185…1185")
    }

    func testUnknownAssetIsShownByIndex() throws {
        var context = context
        context.coinName = { _ in nil }
        let summary = try XCTUnwrap(HyperliquidCoSignVerifier.verify(
            try l1Payload(HLActions.updateLeverage(asset: 3, isCross: false, leverage: 5), kind: .updateLeverage), context: context))
        XCTAssertTrue(summary.lines[0].contains(String(format: "perpsCoSignAsset".localized, "3")))
    }

    func testMissingPreimageIsRefusedNeverBlindSigned() throws {
        var payload = try l1Payload(try orderAction())
        payload.hyperliquid = nil
        assertRefused(payload, .missingPreimage)
    }

    func testTamperedPreimageIsRefused() throws {
        let original = try l1Payload(try orderAction())
        let preimage = try XCTUnwrap(original.hyperliquid)

        var bytes = preimage.actionMsgpack
        // "0.00298" -> "0.00299": still canonical, different action.
        let sizeRange = try XCTUnwrap(bytes.range(of: Data("0.00298".utf8)))
        bytes[sizeRange.upperBound - 1] = UInt8(ascii: "9")
        var tampered = original
        tampered.hyperliquid = HyperliquidActionPreimage(kind: "order", actionMsgpack: bytes, nonce: preimage.nonce,
                                                         expiresAfter: preimage.expiresAfter, isMainnet: true)
        assertRefused(tampered, .digestMismatch)

        tampered.hyperliquid = HyperliquidActionPreimage(kind: "order", actionMsgpack: preimage.actionMsgpack, nonce: preimage.nonce + 1,
                                                         expiresAfter: preimage.expiresAfter, isMainnet: true)
        assertRefused(tampered, .digestMismatch)

        tampered.hyperliquid = HyperliquidActionPreimage(kind: "order", actionMsgpack: preimage.actionMsgpack, nonce: preimage.nonce,
                                                         expiresAfter: (preimage.expiresAfter ?? 0) + 1, isMainnet: true)
        assertRefused(tampered, .digestMismatch)

        tampered.hyperliquid = HyperliquidActionPreimage(kind: "order", actionMsgpack: preimage.actionMsgpack, nonce: preimage.nonce,
                                                         expiresAfter: preimage.expiresAfter, isMainnet: false)
        assertRefused(tampered, .digestMismatch)

        tampered.hyperliquid = HyperliquidActionPreimage(kind: "cancel", actionMsgpack: preimage.actionMsgpack, nonce: preimage.nonce,
                                                         expiresAfter: preimage.expiresAfter, isMainnet: true)
        assertRefused(tampered, .kindMismatch)
    }

    func testNonCanonicalEncodingIsRefused() throws {
        var payload = try l1Payload(HLActions.noop, kind: .noop)
        payload.hyperliquid = HyperliquidActionPreimage(kind: "noop", actionMsgpack: try XCTUnwrap(Data(hexString: "81a474797065d9046e6f6f70")),
                                                        nonce: Self.nonce, expiresAfter: Self.nonce + 60_000, isMainnet: true)
        assertRefused(payload, .nonCanonicalAction)
    }

    /// The digest matches (the initiator signed exactly this), but the action
    /// is not one perps builds: refused by the allowlist.
    func testAllowlistRefusesExtraKeysAndUnknownTypes() throws {
        guard case .map(var entries) = try orderAction() else { return XCTFail("map") }
        entries.append(HLEntry(key: "x", value: .bool(true)))
        assertRefused(try l1Payload(.map(entries)), .unexpectedKeys("x"))

        let transfer = HLValue.object([("type", .string("usdSend")), ("amount", .string("1"))])
        assertRefused(try l1Payload(transfer), .unknownAction("usdSend"))
    }

    func testVaultAddressBuilderAndTimeBounds() throws {
        assertRefused(try l1Payload(try orderAction(), vaultAddress: "0x1234567890abcdef1234567890abcdef12345678"), .vaultAddressSet)
        assertRefused(try l1Payload(try orderAction(builder: HLBuilderFee(builder: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                                                                           tenthsOfBasisPoint: 10))), .builderMismatch)
        assertRefused(try l1Payload(try orderAction(builder: HLBuilderFee(builder: PerpsConfig.builderAddress,
                                                                           tenthsOfBasisPoint: 150))), .builderFeeTooHigh)
        assertRefused(try l1Payload(try orderAction(), expiryMs: 180_001), .expiryTooLong)
        XCTAssertNotNil(try HyperliquidCoSignVerifier.verify(try l1Payload(try orderAction(), expiryMs: 180_000), context: context))

        var noExpiry = try payload(try .l1(.order, action: try orderAction(), nonce: Self.nonce, isMainnet: true))
        assertRefused(noExpiry, .missingExpiry)
        noExpiry.hyperliquid = nil
        assertRefused(noExpiry, .missingPreimage)

        var late = context
        late.nowMs = Self.nonce + 600_001
        assertRefused(try l1Payload(try orderAction()), .nonceOutOfRange, context: late)
        // A nonce far in the future would stretch how long the signature stays live.
        var early = context
        early.nowMs = Self.nonce - 30_001
        assertRefused(try l1Payload(try orderAction()), .nonceOutOfRange, context: early)
        early.nowMs = Self.nonce - 30_000
        XCTAssertNotNil(try HyperliquidCoSignVerifier.verify(try l1Payload(try orderAction()), context: early))
    }

    func testExitEditActionsRender() throws {
        let stop = HLOrderWire(asset: 0, isBuy: false, price: "62000", size: "0.002", reduceOnly: true,
                               type: .trigger(isMarket: true, triggerPrice: "62000", kind: .stopLoss))
        let modify = try XCTUnwrap(HyperliquidCoSignVerifier.verify(
            try l1Payload(HLActions.batchModify([(77, stop)]), kind: .batchModify), context: context))
        XCTAssertTrue(modify.lines[0].contains("77"))
        XCTAssertTrue(modify.lines[0].contains("62,000"))
        XCTAssertTrue(modify.lines[0].contains("0.002"), "the trigger line shows side and size, not only the price")

        // A limit trigger can sit unfillable; a non-reduce-only one can open a position.
        let limitStop = HLOrderWire(asset: 0, isBuy: false, price: "1", size: "0.002", reduceOnly: true,
                                    type: .trigger(isMarket: false, triggerPrice: "62000", kind: .stopLoss))
        assertRefused(try l1Payload(HLActions.batchModify([(77, limitStop)]), kind: .batchModify), .unsupportedTrigger)
        let opening = HLOrderWire(asset: 0, isBuy: false, price: "62000", size: "5", reduceOnly: false,
                                  type: .trigger(isMarket: true, triggerPrice: "62000", kind: .stopLoss))
        assertRefused(try l1Payload(HLActions.batchModify([(77, opening)]), kind: .batchModify), .unsupportedTrigger)

        let cancel = try XCTUnwrap(HyperliquidCoSignVerifier.verify(
            try l1Payload(HLActions.cancel([(0, 77)]), kind: .cancel), context: context))
        XCTAssertEqual(cancel.lines.first, String(format: "perpsCoSignCancel".localized, "77", "BTC"))
    }

    // MARK: - User-signed

    private func withdraw(to destination: String) throws -> CustomMessagePayload {
        try payload(.userSigned(.withdraw3, try HLUserSignedAction.withdraw3(destination: destination, amount: 49.5, nonce: Self.nonce,
                                                                           isMainnet: true, signatureChainId: 0xa4b1)))
    }

    func testWithdrawIsPinnedToThisDevicesOwnVaultAddress() throws {
        let summary = try XCTUnwrap(HyperliquidCoSignVerifier.verify(try withdraw(to: Self.main), context: context))
        XCTAssertEqual(summary.lines.first, String(format: "perpsCoSignWithdraw".localized, "49.5"))
        assertRefused(try withdraw(to: "0x00000000000000000000000000000000000000ff"), .withdrawDestination)
        var noAddress = context
        noAddress.mainAddress = nil
        assertRefused(try withdraw(to: Self.main), .withdrawDestination, context: noAddress)

        var wrongNetwork = try withdraw(to: Self.main)
        wrongNetwork.hyperliquid = HyperliquidActionPreimage(kind: "withdraw3", actionMsgpack: Data(), nonce: Self.nonce, isMainnet: false)
        assertRefused(wrongNetwork, .networkMismatch)
        var wrongTime = try withdraw(to: Self.main)
        wrongTime.hyperliquid = HyperliquidActionPreimage(kind: "withdraw3", actionMsgpack: Data(), nonce: Self.nonce + 1, isMainnet: true)
        assertRefused(wrongTime, .withdrawTimeMismatch)
    }

    func testBuilderApprovalIsPinned() throws {
        func approval(_ builder: String, _ rate: String) throws -> CustomMessagePayload {
            try payload(.userSigned(.approveBuilderFee, try HLUserSignedAction.approveBuilderFee(
                builder: builder, maxFeeRate: rate, nonce: Self.nonce, isMainnet: true, signatureChainId: 0xa4b1)))
        }
        XCTAssertNotNil(try HyperliquidCoSignVerifier.verify(try approval(PerpsConfig.builderAddress, "0.1%"), context: context))
        assertRefused(try approval("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd", "0.1%"), .builderMismatch)
        assertRefused(try approval(PerpsConfig.builderAddress, "0.5%"), .maxFeeTooHigh)
    }

    /// The agent key is device-local, so the joiner can't recompute it: it
    /// shows the full address, and pins the name and the lifetime perps uses.
    func testAgentApprovalIsPinnedToThePerpsNameAndLifetime() throws {
        let agent = "0x5e9ee1089755c3435139848e47e6635505d5a13a"
        func approval(_ name: String?) throws -> CustomMessagePayload {
            try payload(.userSigned(.approveAgent, try HLUserSignedAction.approveAgent(
                agentAddress: agent, agentName: name, nonce: Self.nonce, isMainnet: true, signatureChainId: 0xa4b1)))
        }
        let week = Self.nonce + PerpsConfig.agentLifetimeMs
        let summary = try XCTUnwrap(HyperliquidCoSignVerifier.verify(try approval("vultisig valid_until \(week)"), context: context))
        XCTAssertTrue(summary.lines[0].contains(agent), "the full agent address, not a shortened one")
        assertRefused(try approval(nil), .emptyAgentName)
        assertRefused(try approval("vultisig"), .agentApprovalMismatch)
        assertRefused(try approval("attacker valid_until \(week)"), .agentApprovalMismatch)
        assertRefused(try approval("vultisig valid_until \(Self.nonce - 1)"), .agentApprovalMismatch)
        let tooLong = Self.nonce + PerpsConfig.agentLifetimeMs + HyperliquidCoSignVerifier.maxClockSkewMs + 1
        assertRefused(try approval("vultisig valid_until \(tooLong)"), .agentApprovalMismatch)
        assertRefused(try approval("vultisig valid_until \(HLUserSignedAction.maxAgentLifetimeMs + Self.nonce)"), .agentApprovalMismatch)
    }

    func testUserSignedDomainMustUseTheConfiguredChainId() throws {
        let sdkChain = try payload(.userSigned(.withdraw3, try HLUserSignedAction.withdraw3(
            destination: Self.main, amount: 49.5, nonce: Self.nonce, isMainnet: true, signatureChainId: 0x66eee)))
        assertRefused(sdkChain, .signatureChainMismatch)
    }

    /// Two JSON parsers read the typed data (JSONSerialization here, WalletCore
    /// for the digest): a repeated key could make them disagree, so it is refused.
    func testDuplicateKeysAreRefusedBeforeDetection() throws {
        let hidden = #"{"types":{"EIP712Domain":[{"name":"name","type":"string"}],"Agent":[{"name":"source","type":"string"}]},"#
            + #""primaryType":"Agent","primaryType":"Mail","domain":{"name":"Exchange"},"message":{"source":"a"}}"#
        let payload = CustomMessagePayload(method: "eth_signTypedData_v4", message: hidden, vaultPublicKeyECDSA: "02aa",
                                           vaultLocalPartyID: "iPhone", chain: "Ethereum")
        assertRefused(payload, .duplicateKeys)
        let escaped = #"{"a":1,"a":2}"#
        XCTAssertTrue(try HLJSONKeyScanner.hasDuplicateKeys(escaped), "keys compare after unescaping")
        XCTAssertFalse(try HLJSONKeyScanner.hasDuplicateKeys(#"{"a":{"a":1},"b":[{"a":1},{"a":2}]}"#), "same key in different objects is fine")
        XCTAssertThrowsError(try HLJSONKeyScanner.hasDuplicateKeys(#"{"a":1,}"#))
    }

    func testMarketTriggerWorstPriceIsBounded() throws {
        let far = HLOrderWire(asset: 0, isBuy: false, price: "1", size: "0.002", reduceOnly: true,
                              type: .trigger(isMarket: true, triggerPrice: "62000", kind: .stopLoss))
        assertRefused(try l1Payload(HLActions.batchModify([(77, far)]), kind: .batchModify), .unsupportedTrigger)
        let tenPercent = HLOrderWire(asset: 0, isBuy: false, price: "55800", size: "0.002", reduceOnly: true,
                                     type: .trigger(isMarket: true, triggerPrice: "62000", kind: .stopLoss))
        XCTAssertNotNil(try HyperliquidCoSignVerifier.verify(try l1Payload(HLActions.batchModify([(77, tenPercent)]), kind: .batchModify),
                                                             context: context))
    }

    // MARK: - Golden digests (hyperliquid-python-sdk, vectors/gen_cosign_golden.py)

    /// Every action type the verifier accepts: the SDK's digest equals the
    /// keysign digest of the payload perps builds, and the verifier accepts it.
    func testGoldenDigestsForEveryAcceptedActionMatchTheSDK() throws {
        let expires = Self.nonce + 60_000
        func l1(_ kind: HLExchangeRequest.Kind, _ action: HLValue) throws -> CustomMessagePayload {
            try payload(try .l1(kind, action: action, nonce: Self.nonce, isMainnet: true, expiresAfter: expires))
        }
        let entry = HLOrderWire(asset: 0, isBuy: true, price: "67638", size: "0.00298", reduceOnly: false, type: .limit(.ioc),
                                clientOrderId: "0x0123456789abcdef0123456789abcdef")
        let stop = HLOrderWire(asset: 0, isBuy: false, price: "62000", size: "0.00298", reduceOnly: true,
                               type: .trigger(isMarket: true, triggerPrice: "62000", kind: .stopLoss))
        let order = HLActions.order([entry, stop], grouping: .normalTpsl,
                                    builder: HLBuilderFee(builder: PerpsConfig.builderAddress, tenthsOfBasisPoint: 100))
        let cases: [(String, CustomMessagePayload)] = [
            ("6e8cb5a712c54322641f9a02b96ebf2546a87b61ad59a74ae4292d4acef697c0", try l1(.order, order)),
            ("52811d95906a5bbcbe41f410b60992ddf29dd35d4675e8af52e75f15a4a65fe7", try l1(.cancel, HLActions.cancel([(0, 77)]))),
            ("a86d6014017e648187b5b450cd13a54999f8ce5d54586478e6f4a9c993c1f8c8",
             try l1(.updateLeverage, HLActions.updateLeverage(asset: 0, isCross: false, leverage: 5))),
            ("d1b6379fa8ddad71142398e9c76d1809fc8d46256e9a19127365c6a911d45725",
             try l1(.updateIsolatedMargin, HLActions.updateIsolatedMargin(asset: 0, usd: Decimal(string: "-25.5") ?? 0))),
            ("34dfda9b5778fc4b3e128b38cb14ef2475bfd97e590db6cb3cdecc8d020e3112",
             try payload(.userSigned(.withdraw3, try HLUserSignedAction.withdraw3(
                destination: Self.main, amount: 49.5, nonce: Self.nonce, isMainnet: true, signatureChainId: 0xa4b1)))),
            ("ede06d9d5c819a3b1f589d124eaa19158cd89d1289484ab24de13f86c4ff3e97",
             try payload(.userSigned(.approveBuilderFee, try HLUserSignedAction.approveBuilderFee(
                builder: PerpsConfig.builderAddress, maxFeeRate: "0.1%", nonce: Self.nonce, isMainnet: true, signatureChainId: 0xa4b1)))),
            ("23190d10717ba572c63b1d456ebf8a30757fd757585332b6ceebedb00cc70764",
             try payload(.userSigned(.approveAgent, try HLUserSignedAction.approveAgent(
                agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", agentName: "vultisig valid_until \(Self.nonce + 7 * 86_400_000)",
                nonce: Self.nonce, isMainnet: true, signatureChainId: 0xa4b1))))
        ]
        for (digest, payload) in cases {
            XCTAssertEqual(payload.keysignMessages.first, digest, payload.hyperliquid?.kind ?? "")
            XCTAssertNotNil(try HyperliquidCoSignVerifier.verify(payload, context: context), payload.hyperliquid?.kind ?? "")
        }
    }

    // MARK: - Other payloads

    func testNonHyperliquidPayloadsAreUntouched() throws {
        let permit = #"{"types":{"EIP712Domain":[{"name":"name","type":"string"}],"Mail":[{"name":"x","type":"string"}]},"#
            + #""primaryType":"Mail","domain":{"name":"Ether Mail"},"message":{"x":"hi"}}"#
        let typed = CustomMessagePayload(method: "eth_signTypedData_v4", message: permit, vaultPublicKeyECDSA: "02aa",
                                         vaultLocalPartyID: "iPhone", chain: "Ethereum")
        XCTAssertNil(try HyperliquidCoSignVerifier.verify(typed, context: context))
        let personal = CustomMessagePayload(method: "personal_sign", message: "hello", vaultPublicKeyECDSA: "02aa",
                                            vaultLocalPartyID: "iPhone", chain: "Ethereum")
        XCTAssertNil(try HyperliquidCoSignVerifier.verify(personal, context: context))
    }

    /// The preimage never changes what is signed.
    func testPreimageDoesNotChangeTheDigest() throws {
        var payload = try l1Payload(try orderAction())
        let withPreimage = payload.keysignMessages
        payload.hyperliquid = nil
        XCTAssertEqual(payload.keysignMessages, withPreimage)
    }
}
