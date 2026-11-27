//
//  HyperliquidExchangeDryRunTests.swift
//  VultisigAppTests
//
//  the dry-run /exchange client against the official
//  hyperliquid-python-sdk. The vectors below were produced by
//  VultisigAppTests/Perps/Vectors/gen_exchange_sdk.py, which builds every action
//  the way `hyperliquid/exchange.py` does, signs with the SDK's public test
//  key and records the body `_post_action` posts. One vector
//  (`withdraw3_testnet_sdk_test`) is the SDK's own `signing_test.py` case.
//  Nothing here talks to the network or to a vault.
//

import WalletCore
import XCTest
@testable import VultisigApp

final class HyperliquidExchangeDryRunTests: XCTestCase {
    private static let sdkTestKey = "0123456789012345678901234567890123456789012345678901234567890123"
    private static let nonce: UInt64 = 1_731_400_000_000
    private static let vault = "0x1234567890abcdef1234567890abcdef12345678"
    private static let agent = "0x5e9ee1089755c3435139848e47e6635505d5a13a"
    private static let builder = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

    private static let vectorsJSON = #"""
{"l1":[{"name":"order_market_ioc_builder","msgpack":"84a474797065a56f72646572a66f72646572739186a16100a162c3a170a53637363338a173a7302e3030313439a172c2a17481a56c696d697481a3746966a3496f63a867726f7570696e67a26e61a76275696c64657282a162d92a307861626364656661626364656661626364656661626364656661626364656661626364656661626364a16632",
"connectionId":"67d43fa2cca3674237ce3da1af9713f2fbe3b7032e11d9d56d81f1a773f6bb8b","digest":"f99fec00899ce766d765311363db7fc515e5607fc35a638f89ca897053a52424",
"body":{"action":{"type":"order","orders":[{"a":0,"b":true,"p":"67638","s":"0.00149","r":false,"t":{"limit":{"tif":"Ioc"}}}],
"grouping":"na","builder":{"b":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","f":50}},"nonce":1731400000000,"signature":{"r":"0xfaf784b492361d88467625d9fb0ee50994eb75342c773ce2fb4fdcaf2860aad",
"s":"0x4971ee8bfe7f71a38e60a49c431e562982843fb5b58e958fbdd565d8c427cedd","v":28},"vaultAddress":null,"expiresAfter":null}},
{"name":"order_limit_sl_expires","msgpack":"83a474797065a56f72646572a66f72646572739286a16101a162c3a170a432343030a173a4302e3234a172c2a17481a56c696d697481a3746966a347746386a16101a162c2a170a432323030a173a4302e3234a172c3a17481a77472696767657283a869734d61726b6574c3a9747269676765725078a432323030a47470736ca2736ca867726f7570696e67aa6e6f726d616c5470736c",
"connectionId":"ca3df4eeace209f52346dbde91b8a4235eb823b2e87d76d69ac0b780bbb2a839","digest":"02db458905c2cce8c6c85fef14a4be30ebe0b0437dca0fceb9ad438954dd50d2",
"body":{"action":{"type":"order","orders":[{"a":1,"b":true,"p":"2400","s":"0.24","r":false,"t":{"limit":{"tif":"Gtc"}}},
{"a":1,"b":false,"p":"2200","s":"0.24","r":true,"t":{"trigger":{"isMarket":true,"triggerPx":"2200","tpsl":"sl"}}}],
"grouping":"normalTpsl"},"nonce":1731400000000,"signature":{"r":"0xd2490d50af9325e4860eee6b42813093a94e93b8ce1702b74705cddbddd17725",
"s":"0x6d55a32e1b197212af35665330a4c92299ccdeaf3a48411a4a7966227322d83","v":27},"vaultAddress":null,"expiresAfter":1731400060000}},
{"name":"order_vault_address","msgpack":"83a474797065a56f72646572a66f72646572739186a16105a162c2a170a53138352e35a173a4352e3831a172c3a17481a56c696d697481a3746966a3496f63a867726f7570696e67a26e61",
"connectionId":"0637a73766bad7fb66cfb78f65195ec133dc640492003f9b92571bacd5d83a33","digest":"f7060ad2a1f9eca526b0e984f8ccb48762424c37a284ee7fa878c4de28f9d0c8",
"body":{"action":{"type":"order","orders":[{"a":5,"b":false,"p":"185.5","s":"5.81","r":true,"t":{"limit":{"tif":"Ioc"}}}],
"grouping":"na"},"nonce":1731400000000,"signature":{"r":"0xc122ab8756271fef09f8d4f7b38f14e1bd5316ada04ab35d8a271c40bcd8b87",
"s":"0x12249caec4c8ecfb727775671a54c4602c100f3e928b930115b7d0061344f242","v":28},"vaultAddress":"0x1234567890abcdef1234567890abcdef12345678",
"expiresAfter":null}},{"name":"cancel","msgpack":"82a474797065a663616e63656ca763616e63656c739182a16100a16fce075bcd15",
"connectionId":"3ef01fd7e008c3fa9f09d4c84a444e05c536ec00ffb2ecf5512ad6666782db3a","digest":"5f24da45b96005c50d1945f1145a5ce73a244c9f4cbd4db7042c491b7536fb0e",
"body":{"action":{"type":"cancel","cancels":[{"a":0,"o":123456789}]},"nonce":1731400000000,"signature":{"r":"0xe10c9ed27da9dc875cb78c72b21d7b2b47795b8abbaf54513615e2caba777db2",
"s":"0x22b2e49b67fdc1de9a87acf8e76a81d984e9f8c4e700d276cbae21c47c0b6870","v":28},"vaultAddress":null,"expiresAfter":null}},
{"name":"cancel_expires","msgpack":"82a474797065a663616e63656ca763616e63656c739282a16101a16f2a82a16105a16f4d","connectionId":"1841bfe0217bf45e2253b2c815738cc7481b6c92af2b7bb72f0e02575c119017",
"digest":"02b076d6edb28e8ff57b783c6328e9bad8065747659235a8fed6871b323d9980","body":{"action":{"type":"cancel","cancels":[{"a":1,
"o":42},{"a":5,"o":77}]},"nonce":1731400000000,"signature":{"r":"0xa8939874c2a52f15d5589d060414d395abd07b9ba772cb0031d11eb2bc945e0c",
"s":"0x7c7b9f5729595c7f016e6dd1de2b17abc06f12280795330bd1618328cfa6b7da","v":27},"vaultAddress":null,"expiresAfter":1731400030000}},
{"name":"update_leverage_isolated","msgpack":"84a474797065ae7570646174654c65766572616765a5617373657401a7697343726f7373c2a86c6576657261676503",
"connectionId":"e5d8bd234da7f3afd52c876246bbdd3554758a6257d100dda31a239a0b8851f5","digest":"a8b5fc4d3e0bd9767de7b1648c6f9c82bd620206dd95045b4f47748d95e63358",
"body":{"action":{"type":"updateLeverage","asset":1,"isCross":false,"leverage":3},"nonce":1731400000000,"signature":{"r":"0xfa9b119d20b3e06d26d21605d82b9dd31cb3b692548d994976b4bcead7a384ba",
"s":"0x72b12c74d318b83c88c3a9c242dc4abfee0d6c6156d2a4745713b16138c7baf4","v":28},"vaultAddress":null,"expiresAfter":null}},
{"name":"update_isolated_margin_add","msgpack":"84a474797065b475706461746549736f6c617465644d617267696ea5617373657405a56973427579c3a46e746c69ce05f5e100",
"connectionId":"e6475ac7ea3c76a509cf765e87a76b76c6f0296725f718e9a49157bb950dd30d","digest":"b5ff89ed937eb2ba10a8ae325bbf6ab7bd334f7546836e9232be460e54c90fda",
"body":{"action":{"type":"updateIsolatedMargin","asset":5,"isBuy":true,"ntli":100000000},"nonce":1731400000000,
"signature":{"r":"0xd56ed2d96fde56c8ce45b0e88644ba1fe419d01812e5eff11e9216af6ac0fd7d","s":"0x7d868ace511e4b439cf4a70374b693c2411e88aadc7afb00a756b003a6cf3294",
"v":27},"vaultAddress":null,"expiresAfter":null}},{"name":"update_isolated_margin_remove","msgpack":"84a474797065b475706461746549736f6c617465644d617267696ea5617373657405a56973427579c3a46e746c69d2fe7ae6a0",
"connectionId":"e414fc2d6d392b16018f7b473444a5a31b6da265be2ddad64391c094654476be","digest":"7691d41c9595d40aefd9fb3cc5b2998452ea22f493e35c691ec0ffbceafde7d2",
"body":{"action":{"type":"updateIsolatedMargin","asset":5,"isBuy":true,"ntli":-25500000},"nonce":1731400000000,
"signature":{"r":"0x33b0733e9d3af7f22f6f548f6ae144150ae5af264b28e5b7cecbcea22d712fb8","s":"0x7f108c9b5712402c271d225dd254092497dbd5e73223e5598079d2d0e41a6566",
"v":27},"vaultAddress":null,"expiresAfter":null}}],"userSigned":[{"name":"approve_agent_valid_until","digest":"abd132aaa31fbcc061d12529458d129b7249adcc3cae29b92e9b4c279c2db52a",
"body":{"action":{"type":"approveAgent","agentAddress":"0x5e9ee1089755c3435139848e47e6635505d5a13a","agentName":"vultisig valid_until 1732004800000",
"nonce":1731400000000,"signatureChainId":"0x66eee","hyperliquidChain":"Mainnet"},"nonce":1731400000000,"signature":{"r":"0xef0b5f6c93a655e83f2aad25b8c4cdad8c0e9f4daf53ec7f06b452e7124ff615",
"s":"0x4b28dab0a96c616bbaf21123c097132b11a6155609d62acfd0855f3b55f8ef8b","v":28},"vaultAddress":null,"expiresAfter":null}},
{"name":"approve_agent_unnamed","digest":"c295b4e251bbb8d34da848961a23575b18f1eae63a4ea60541ede54e2014d004","body":{"action":{"type":"approveAgent",
"agentAddress":"0x5e9ee1089755c3435139848e47e6635505d5a13a","nonce":1731400000000,"signatureChainId":"0x66eee",
"hyperliquidChain":"Mainnet"},"nonce":1731400000000,"signature":{"r":"0xad79cf4beb90a7816529f6dd691a28bd6bf902bd80ea73037173a96c818e180f",
"s":"0x23d2cf6bb5015e0e1a867962757ddaf1ac598cde95023e34a79fee36e49048ac","v":28},"vaultAddress":null,"expiresAfter":null}},
{"name":"approve_builder_fee","digest":"8c6fd180e7ddfba0f763ad99d493ab4912fcf4d4d734e1fa450f752446f525d8","body":{"action":{"maxFeeRate":"0.05%",
"builder":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","nonce":1731400000000,"type":"approveBuilderFee","signatureChainId":"0x66eee",
"hyperliquidChain":"Mainnet"},"nonce":1731400000000,"signature":{"r":"0x441124516e0a8b44079d5a4a8ed30e6b135ffc8247425310918c91d1e961a2c2",
"s":"0x1c2532520f0416f7377ed9a232d631e358044d77e0f8cf32e25b6a669c0e20af","v":28},"vaultAddress":null,"expiresAfter":null}},
{"name":"withdraw3","digest":"3cd3ca76beb5c69c28e3b7fff6d0fd94412728130e07e79c6c8d82ec23996a25","body":{"action":{"destination":"0x9d7c000000000000000000000000000000003003",
"amount":"499","time":1731400000000,"type":"withdraw3","signatureChainId":"0x66eee","hyperliquidChain":"Mainnet"},
"nonce":1731400000000,"signature":{"r":"0xae91a55c7e0415670fe7031205a6d6430699f01f3ce0223544ac2c2c6addda43","s":"0x72fdf5524ad688b3bfdf844768aba768a9a95372f15d8ef463431856ca7efb2",
"v":27},"vaultAddress":null,"expiresAfter":null}},{"name":"withdraw3_testnet_sdk_test","digest":"8080d06f566813165cec60d85300445133b3439e9c92e10b93ed510372608899",
"body":{"action":{"destination":"0x5e9ee1089755c3435139848e47e6635505d5a13a","amount":"1","time":1687816341423,
"type":"withdraw3","signatureChainId":"0x66eee","hyperliquidChain":"Testnet"},"nonce":1687816341423,"signature":{"r":"0x8363524c799e90ce9bc41022f7c39b4e9bdba786e5f9c72b20e43e1462c37cf9",
"s":"0x58b1411a775938b83e29182e8ef74975f9054c8e97ebf5ec2dc8d51bfc893881","v":28},"vaultAddress":null,"expiresAfter":null}}],
"discrepancies":{"sdkCanonicalOrderWire":{"type":"order","orders":[{"a":0,"b":true,"p":"30000","s":"0.001","r":false,
"t":{"limit":{"tif":"Gtc"}}}],"grouping":"na"},"sdkFloatToWire30000":"30000","connectionId_contractDoc_abprst_30000.0":"6c938d29790e8bddbd876ccffff801db90bd459e814dddc034d743a634b39715",
"connectionId_keyOrderFixed_abpsrt_30000.0":"9f6bee2480472d99b641e8e9e5f6750cc50e3590ecea8366c0a8608435418d28",
"connectionId_sdkCanonical_abpsrt_30000":"2f54f919e286785cc31af0928e81d322aa1e9e9044a2801ede266058e88989c0"}}
"""#

    private static let vectors: [String: [String: Any]] = {
        guard let data = vectorsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: [String: Any]] = [:]
        for group in ["l1", "userSigned"] {
            for item in root[group] as? [[String: Any]] ?? [] {
                if let name = item["name"] as? String { out[name] = item }
            }
        }
        out["discrepancies"] = root["discrepancies"] as? [String: Any]
        return out
    }()

    // MARK: - Helpers

    private func sign(_ request: HLExchangeRequest) throws -> HLExchangeRequest {
        let key = try XCTUnwrap(PrivateKey(data: try XCTUnwrap(Data(hexString: Self.sdkTestKey))))
        let raw = try XCTUnwrap(key.sign(digest: request.digest, curve: .secp256k1))
        let signer = PerpsSignerGuard.address(of: key.getPublicKeySecp256k1(compressed: true))
        return try request.signed(try XCTUnwrap(HLSignature(recoverable: raw)), expected: signer)
    }

    private func json(_ text: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
    }

    private func assertMatchesSDK(_ request: HLExchangeRequest, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let vector = try XCTUnwrap(Self.vectors[name], "missing vector \(name)", file: file, line: line)
        if let msgpack = vector["msgpack"] as? String {
            XCTAssertEqual(try HLMsgPack.encode(request.action).hexString, msgpack, "\(name) msgpack", file: file, line: line)
        }
        if let connectionId = vector["connectionId"] as? String {
            let computed = try HLActionHasher.connectionId(action: request.action, nonce: request.nonce,
                                                           vaultAddress: request.vaultAddress, expiresAfter: request.expiresAfter)
            XCTAssertEqual(computed.hexString, connectionId, "\(name) connectionId", file: file, line: line)
        }
        XCTAssertEqual(request.digest.hexString, vector["digest"] as? String, "\(name) digest", file: file, line: line)
        let signed = try sign(request)
        let sdkBody = try XCTUnwrap(vector["body"] as? NSDictionary)
        XCTAssertEqual(try json(signed.jsonBody), sdkBody, "\(name) posted body", file: file, line: line)
    }

    private func order(_ coinAsset: Int, _ isBuy: Bool, _ price: String, _ size: String, _ reduceOnly: Bool, _ type: HLOrderType) -> HLOrderWire {
        HLOrderWire(asset: coinAsset, isBuy: isBuy, price: price, size: size, reduceOnly: reduceOnly, type: type)
    }

    // MARK: - L1 actions

    func testMarketOrderWithBuilderMatchesSDK() throws {
        let action = HLActions.order([order(0, true, "67638", "0.00149", false, .limit(.ioc))],
                                     builder: HLBuilderFee(builder: Self.builder, tenthsOfBasisPoint: 50))
        try assertMatchesSDK(try .l1(.order, action: action, nonce: Self.nonce, isMainnet: true), "order_market_ioc_builder")
    }

    func testLimitOrderWithStopAndExpiresAfterMatchesSDK() throws {
        let action = HLActions.order([
            order(1, true, "2400", "0.24", false, .limit(.gtc)),
            order(1, false, "2200", "0.24", true, .trigger(isMarket: true, triggerPrice: "2200", kind: .stopLoss))
        ], grouping: .normalTpsl)
        try assertMatchesSDK(try .l1(.order, action: action, nonce: Self.nonce, isMainnet: true, expiresAfter: Self.nonce + 60_000),
                             "order_limit_sl_expires")
    }

    func testOrderOnVaultAddressMatchesSDK() throws {
        let action = HLActions.order([order(5, false, "185.5", "5.81", true, .limit(.ioc))])
        try assertMatchesSDK(try .l1(.order, action: action, nonce: Self.nonce, isMainnet: true, vaultAddress: Self.vault), "order_vault_address")
    }

    func testCancelMatchesSDK() throws {
        try assertMatchesSDK(try .l1(.cancel, action: HLActions.cancel([(0, 123_456_789)]), nonce: Self.nonce, isMainnet: true), "cancel")
        try assertMatchesSDK(try .l1(.cancel, action: HLActions.cancel([(1, 42), (5, 77)]), nonce: Self.nonce, isMainnet: true,
                                     expiresAfter: Self.nonce + 30_000), "cancel_expires")
    }

    func testUpdateLeverageMatchesSDK() throws {
        let action = HLActions.updateLeverage(asset: 1, isCross: false, leverage: 3)
        try assertMatchesSDK(try .l1(.updateLeverage, action: action, nonce: Self.nonce, isMainnet: true), "update_leverage_isolated")
    }

    func testUpdateIsolatedMarginMatchesSDK() throws {
        try assertMatchesSDK(try .l1(.updateIsolatedMargin, action: HLActions.updateIsolatedMargin(asset: 5, usd: 100),
                                     nonce: Self.nonce, isMainnet: true), "update_isolated_margin_add")
        let remove = try XCTUnwrap(Decimal(string: "-25.5"))
        try assertMatchesSDK(try .l1(.updateIsolatedMargin, action: HLActions.updateIsolatedMargin(asset: 5, usd: remove),
                                     nonce: Self.nonce, isMainnet: true), "update_isolated_margin_remove")
    }

    // MARK: - User-signed actions (vault only)

    func testApproveAgentWithExpiryMatchesSDK() throws {
        let name = HLUserSignedAction.agentName("vultisig", validUntilMs: Self.nonce + 7 * 86_400_000)
        XCTAssertEqual(name, "vultisig valid_until 1732004800000")
        let signed = try HLUserSignedAction.approveAgent(agentAddress: Self.agent, agentName: name, nonce: Self.nonce, isMainnet: true)
        try assertMatchesSDK(.userSigned(.approveAgent, signed), "approve_agent_valid_until")
    }

    func testUnnamedApproveAgentMatchesSDK() throws {
        let signed = try HLUserSignedAction.approveAgent(agentAddress: Self.agent, agentName: nil, nonce: Self.nonce, isMainnet: true)
        try assertMatchesSDK(.userSigned(.approveAgent, signed), "approve_agent_unnamed")
    }

    func testApproveBuilderFeeMatchesSDK() throws {
        let signed = try HLUserSignedAction.approveBuilderFee(builder: Self.builder, maxFeeRate: "0.05%", nonce: Self.nonce, isMainnet: true)
        try assertMatchesSDK(.userSigned(.approveBuilderFee, signed), "approve_builder_fee")
    }

    func testWithdraw3MatchesSDK() throws {
        let signed = try HLUserSignedAction.withdraw3(destination: "0x9d7c000000000000000000000000000000003003", amount: 499,
                                                      nonce: Self.nonce, isMainnet: true)
        XCTAssertEqual(signed.action["time"], .uint(Self.nonce), "withdraw3 signs `time`, equal to the nonce")
        try assertMatchesSDK(.userSigned(.withdraw3, signed), "withdraw3")
    }

    /// The SDK's own `test_sign_withdraw_from_bridge_action`, r/s/v pinned to production.
    func testWithdraw3MatchesPythonSDKSigningTest() throws {
        let signed = try HLUserSignedAction.withdraw3(destination: Self.agent, amount: 1, nonce: 1_687_816_341_423, isMainnet: false)
        try assertMatchesSDK(.userSigned(.withdraw3, signed), "withdraw3_testnet_sdk_test")
        let body = try json(try sign(.userSigned(.withdraw3, signed)).jsonBody)
        let signature = try XCTUnwrap(body["signature"] as? NSDictionary)
        XCTAssertEqual(signature["r"] as? String, "0x8363524c799e90ce9bc41022f7c39b4e9bdba786e5f9c72b20e43e1462c37cf9")
        XCTAssertEqual(signature["s"] as? String, "0x58b1411a775938b83e29182e8ef74975f9054c8e97ebf5ec2dc8d51bfc893881")
        XCTAssertEqual(signature["v"] as? Int, 28)
    }

    func testUserSignedRequestsNeverCarryVaultOrExpiry() throws {
        let signed = try HLUserSignedAction.withdraw3(destination: Self.agent, amount: 10, nonce: Self.nonce, isMainnet: true)
        let request = HLExchangeRequest.userSigned(.withdraw3, signed)
        XCTAssertNil(request.vaultAddress)
        XCTAssertNil(request.expiresAfter)
        XCTAssertTrue(request.signRequest.isUserSigned)
        XCTAssertThrowsError(try LocalAgentPerpsSigner(privateKeyData: try XCTUnwrap(Data(hexString: Self.sdkTestKey))).prepare(request.signRequest))
    }

    // MARK: - Dry-run client and nonces

    func testNoncesAreStrictlyIncreasingWithinOneMillisecond() {
        let frozen = Date(timeIntervalSince1970: 1_731_400_000)
        let source = HLNonceSource { frozen }
        let first = source.next()
        let second = source.next()
        XCTAssertEqual(first, 1_731_400_000_000)
        XCTAssertEqual(second, first + 1)
    }

    @MainActor
    func testDryRunOnlyLogsAndReturnsTheBody() throws {
        let client = HyperliquidExchangeDryRunClient()
        let request = try HLExchangeRequest.l1(.cancel, action: HLActions.cancel([(0, 1)]), nonce: Self.nonce, isMainnet: true)
        guard case .dryRun(let body) = client.submit(request) else { return XCTFail("expected a dry run") }
        XCTAssertEqual(client.log.count, 1)
        XCTAssertEqual(client.log.first?.json, body)
        let parsed = try json(body)
        XCTAssertEqual((parsed["signature"] as? NSDictionary)?["pendingVaultKeysign"] as? String, "0x" + request.digest.hexString)
        XCTAssertFalse(PerpsConfig.allowsSigning)
    }

    /// The builder is Vultisig's EVM fee address at 10 bps, lowercase on the order and the approval.
    func testBuilderIsTheVultisigFeeAddressAtTenBps() throws {
        let expected = "0x8e247a480449c84a5fdd25974a8501f3efa4abb9"
        XCTAssertEqual(PerpsConfig.builderAddress.lowercased(), expected)
        XCTAssertEqual(PerpsConfig.builderFeeTenthsBp, 100)
        XCTAssertEqual(PerpsConfig.builderMaxFeeRate, "0.1%")
        let action = HLActions.order([order(0, true, "67638", "0.00149", false, .limit(.ioc))], builder: PerpsConfig.builderFee)
        XCTAssertEqual(action["builder"], .object([("b", .string(expected)), ("f", .int(100))]))
        let approval = try HLUserSignedAction.approveBuilderFee(builder: PerpsConfig.builderAddress, maxFeeRate: PerpsConfig.builderMaxFeeRate,
                                                               nonce: Self.nonce, isMainnet: true)
        XCTAssertEqual(approval.action["builder"], .string(expected))
        XCTAssertEqual(approval.action["maxFeeRate"], .string("0.1%"))
    }

    func testPlannerStepsCarryShortExpiry() throws {
        let market = PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: 66_969,
                                 midPrice: 66_969, previousDayPrice: 66_000, hourlyFunding: 0.0000125, openInterest: 1, dayVolume: 1)
        let ticket = PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated, limitPrice: nil, takeProfit: nil, stopLoss: 62_500)
        let plan = try PerpsOrderPlanner.plan(market: market, ticket: ticket, nonce: Self.nonce, builder: PerpsConfig.builderFee)
        let requests = plan.requests
        XCTAssertEqual(requests.map(\.kind), [.updateLeverage, .order])
        XCTAssertEqual(requests.map(\.nonce), [Self.nonce, Self.nonce + 1])
        XCTAssertEqual(requests.map(\.expiresAfter), [Self.nonce + 60_000, Self.nonce + 60_001])
    }
}
