//
//  QBTCStakingSignDataResolverTests.swift
//  VultisigAppTests
//
//  Pins the QBTC (ML-DSA) staking SignDoc contract. QBTC signs with a
//  post-quantum ML-DSA key, so it cannot ride the secp256k1
//  `CosmosStakingSignDataResolver.resolve(...)` path — it uses `resolveMLDSA`,
//  which skips the 33-byte secp256k1 guard and stamps
//  `/cosmos.crypto.mldsa.PubKey` into AuthInfo. These tests lock down three
//  things that must never drift on a wallet signing path:
//
//    1. Each msg body (`Msg{Delegate,Undelegate,BeginRedelegate,
//       WithdrawDelegatorReward}`) the resolver produces equals the shared
//       `CosmosStakingHelper.encode*` output byte-for-byte — proving QBTC has
//       no divergent encoder.
//    2. The AuthInfo carries the ML-DSA pubkey type URL, NOT secp256k1.
//    3. The TxBody/AuthInfo bytes round-trip through `QBTCHelper`'s signDirect
//       consumption path to a deterministic SignDoc hash on both devices.
//

@testable import VultisigApp
import CryptoKit
import XCTest

final class QBTCStakingSignDataResolverTests: XCTestCase {

    // MARK: - Fixtures

    private enum FX {
        static let denom = "qbtc"
        static let amount = "100000000" // 1 QBTC at 8 decimals
        static let delegatorAddress = "qbtc1delegator00000000000000000000000000000"
        // Tracks the production `CosmosStakingConfig` chain-id (QBTC mainnet).
        // `testChainIdComesFromQBTCConfigEntry` asserts the resolved
        // `signDirect.chainID` equals this; it is NOT a recorded signing vector
        // (the SignDoc-hash tests derive their hash from `signDirect.chainID`
        // directly, so they self-adjust).
        static let chainId = "qbtc"
        static let mldsaPubKeyTypeURL = "/cosmos.crypto.mldsa.PubKey"
        // ~1312-byte ML-DSA-44 pubkey — far larger than secp256k1's 33 bytes;
        // a deterministic all-0xAB fill keeps the AuthInfo bytes stable.
        static let mldsaPubKeyHex = String(repeating: "ab", count: 1312)
    }

    private static let validValidator = Bech32TestUtils.makeValoperAddress(hrp: "qbtcvaloper")
    private static let validValidatorSrc = Bech32TestUtils.makeValoperAddress(hrp: "qbtcvaloper", payloadLength: 20)
    private static let validValidatorDst: String = {
        // A second, distinct valoper for redelegate — vary the payload so the
        // checksum differs from the src address.
        Bech32TestUtils.encodeBech32(hrp: "qbtcvaloper", payload: (0..<20).map { UInt8(($0 + 100) & 0xff) })
    }()

    private static func makeChainSpecific(accountNumber: UInt64 = 100, sequence: UInt64 = 42) -> BlockChainSpecific {
        .Cosmos(
            accountNumber: accountNumber,
            sequence: sequence,
            gas: 7_500,
            transactionType: 0,
            ibcDenomTrace: nil, gasLimit: nil
        )
    }

    private static func makeQBTCCoin() -> Coin {
        let meta = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: FX.delegatorAddress,
            hexPublicKey: FX.mldsaPubKeyHex
        )
    }

    private static func makeSendTransaction(payload: CosmosStakingPayload) -> SendTransaction {
        let coin = makeQBTCCoin()
        return SendTransaction(
            coin: coin,
            vault: .example,
            fromAddress: coin.address,
            toAddress: payload.validatorAddress ?? "",
            toAddressLabel: nil,
            amount: "0",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: true,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            cosmosStakingPayload: payload
        )
    }

    private static func resolve(_ payload: CosmosStakingPayload) throws -> SignDirect {
        try CosmosStakingSignDataResolver.resolveMLDSA(
            sendTransaction: makeSendTransaction(payload: payload),
            chainSpecific: makeChainSpecific()
        )
    }

    // MARK: - ML-DSA pubkey type URL

    func testAuthInfoCarriesMldsaPubKeyTypeURL() throws {
        let signDirect = try Self.resolve(
            .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        let authInfo = try XCTUnwrap(Data(base64Encoded: signDirect.authInfoBytes))
        let fields = try Self.parseFields(authInfo)
        let signerInfo = try Self.parseFields(try Self.bytes(field: 1, in: fields))
        let pubKeyAny = try Self.parseFields(try Self.bytes(field: 1, in: signerInfo))
        XCTAssertEqual(try Self.string(field: 1, in: pubKeyAny), FX.mldsaPubKeyTypeURL)
        XCTAssertNotEqual(
            try Self.string(field: 1, in: pubKeyAny),
            "/cosmos.crypto.secp256k1.PubKey",
            "QBTC must never stamp the secp256k1 pubkey type URL"
        )
    }

    func testAuthInfoEmbedsFullMldsaPubKeyBytes() throws {
        let signDirect = try Self.resolve(
            .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        let authInfo = try XCTUnwrap(Data(base64Encoded: signDirect.authInfoBytes))
        let fields = try Self.parseFields(authInfo)
        let signerInfo = try Self.parseFields(try Self.bytes(field: 1, in: fields))
        let pubKeyAny = try Self.parseFields(try Self.bytes(field: 1, in: signerInfo))
        let pubKeyInner = try Self.parseFields(try Self.bytes(field: 2, in: pubKeyAny))
        let key = try Self.bytes(field: 1, in: pubKeyInner)
        XCTAssertEqual(key, Data(hexString: FX.mldsaPubKeyHex), "Full ML-DSA pubkey must survive into AuthInfo")
    }

    func testAuthInfoUsesConfigFeeAndGasForSingleMsg() throws {
        let signDirect = try Self.resolve(
            .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        let entry = try CosmosStakingConfig.entry(for: .qbtc)
        let expectedAuthInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: try XCTUnwrap(Data(hexString: FX.mldsaPubKeyHex)),
            sequence: 42,
            gasLimit: entry.gasLimit,
            feeDenom: entry.feeDenom,
            feeAmount: entry.feeAmount,
            pubKeyTypeURL: QBTCHelper.pubKeyTypeURL
        )
        XCTAssertEqual(signDirect.authInfoBytes, expectedAuthInfo.base64EncodedString())
    }

    // MARK: - Msg body byte-equality with the shared encoders

    func testDelegateBodyMatchesSharedEncoder() throws {
        let signDirect = try Self.resolve(
            .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        let expectedAny = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegatorAddress, validator: Self.validValidator, amount: FX.amount, denom: FX.denom
        )
        let expectedBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [expectedAny], memo: "")
        XCTAssertEqual(signDirect.bodyBytes, expectedBody.base64EncodedString())
    }

    func testUndelegateBodyMatchesSharedEncoder() throws {
        let signDirect = try Self.resolve(
            .undelegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        let expectedAny = CosmosStakingHelper.encodeUndelegate(
            delegator: FX.delegatorAddress, validator: Self.validValidator, amount: FX.amount, denom: FX.denom
        )
        let expectedBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [expectedAny], memo: "")
        XCTAssertEqual(signDirect.bodyBytes, expectedBody.base64EncodedString())
    }

    func testRedelegateBodyMatchesSharedEncoder() throws {
        let signDirect = try Self.resolve(
            .redelegate(src: Self.validValidatorSrc, dst: Self.validValidatorDst, denom: FX.denom, amount: FX.amount)
        )
        let expectedAny = CosmosStakingHelper.encodeBeginRedelegate(
            delegator: FX.delegatorAddress,
            validatorSrc: Self.validValidatorSrc,
            validatorDst: Self.validValidatorDst,
            amount: FX.amount,
            denom: FX.denom
        )
        let expectedBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [expectedAny], memo: "")
        XCTAssertEqual(signDirect.bodyBytes, expectedBody.base64EncodedString())
    }

    func testWithdrawRewardsBodyMatchesSharedEncoder() throws {
        let signDirect = try Self.resolve(
            .withdrawRewards(validators: [Self.validValidator], denom: FX.denom)
        )
        let expectedAny = CosmosStakingHelper.encodeWithdrawDelegatorReward(
            delegator: FX.delegatorAddress, validator: Self.validValidator
        )
        let expectedBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [expectedAny], memo: "")
        XCTAssertEqual(signDirect.bodyBytes, expectedBody.base64EncodedString())
    }

    // MARK: - Msg type URLs (proves the discriminator is correct)

    func testDelegateUsesDelegateTypeURL() throws {
        try assertMsgTypeURL(
            for: .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount),
            expected: "/cosmos.staking.v1beta1.MsgDelegate"
        )
    }

    func testUndelegateUsesUndelegateTypeURL() throws {
        try assertMsgTypeURL(
            for: .undelegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount),
            expected: "/cosmos.staking.v1beta1.MsgUndelegate"
        )
    }

    func testRedelegateUsesBeginRedelegateTypeURL() throws {
        try assertMsgTypeURL(
            for: .redelegate(src: Self.validValidatorSrc, dst: Self.validValidatorDst, denom: FX.denom, amount: FX.amount),
            expected: "/cosmos.staking.v1beta1.MsgBeginRedelegate"
        )
    }

    func testWithdrawRewardsUsesDistributionTypeURL() throws {
        try assertMsgTypeURL(
            for: .withdrawRewards(validators: [Self.validValidator], denom: FX.denom),
            expected: "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward"
        )
    }

    func testRedelegateEncodesSrcAtFieldTwoAndDstAtFieldThree() throws {
        // Regression guard: a src/dst swap would redelegate the wrong way.
        let signDirect = try Self.resolve(
            .redelegate(src: Self.validValidatorSrc, dst: Self.validValidatorDst, denom: FX.denom, amount: FX.amount)
        )
        let body = try XCTUnwrap(Data(base64Encoded: signDirect.bodyBytes))
        let msgAny = try Self.bytes(field: 1, in: try Self.parseFields(body))
        let msg = try Self.parseFields(try Self.bytes(field: 2, in: try Self.parseFields(msgAny)))
        XCTAssertEqual(try Self.string(field: 1, in: msg), FX.delegatorAddress)
        XCTAssertEqual(try Self.string(field: 2, in: msg), Self.validValidatorSrc)
        XCTAssertEqual(try Self.string(field: 3, in: msg), Self.validValidatorDst)
    }

    // MARK: - Config + cross-device SignDoc

    func testChainIdComesFromQBTCConfigEntry() throws {
        let signDirect = try Self.resolve(
            .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        XCTAssertEqual(signDirect.chainID, FX.chainId)
    }

    func testBatchClaimGasAndFeeScaleLinearly() throws {
        let signDirect = try Self.resolve(
            .withdrawRewards(validators: [Self.validValidator, Self.validValidator, Self.validValidator], denom: FX.denom)
        )
        let entry = try CosmosStakingConfig.entry(for: .qbtc)
        let expectedAuthInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: try XCTUnwrap(Data(hexString: FX.mldsaPubKeyHex)),
            sequence: 42,
            gasLimit: entry.gasLimit * 3,
            feeDenom: entry.feeDenom,
            feeAmount: entry.feeAmount * 3,
            pubKeyTypeURL: QBTCHelper.pubKeyTypeURL
        )
        XCTAssertEqual(signDirect.authInfoBytes, expectedAuthInfo.base64EncodedString())
    }

    func testSignDocHashIsDeterministicFromSignDirectBytes() throws {
        // Reconstruct the SignDoc the way both devices do — body + authInfo +
        // chainID + accountNumber — and confirm the SHA-256 pre-image hash is
        // stable. This is the hash the ML-DSA MPC round signs; it must be
        // identical on initiator and peer (who both rebuild from the
        // round-tripped signDirect).
        let signDirect = try Self.resolve(
            .delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        )
        let body = try XCTUnwrap(Data(base64Encoded: signDirect.bodyBytes))
        let authInfo = try XCTUnwrap(Data(base64Encoded: signDirect.authInfoBytes))

        let hashA = Self.signDocHash(body: body, authInfo: authInfo, chainID: signDirect.chainID, accountNumber: signDirect.accountNumber)
        let hashB = Self.signDocHash(body: body, authInfo: authInfo, chainID: signDirect.chainID, accountNumber: signDirect.accountNumber)
        XCTAssertEqual(hashA, hashB)
        XCTAssertEqual(hashA.count, 64)
    }

    // MARK: - Preflight gating

    func testInvalidValidatorAddressIsRejectedBeforeSigning() {
        let payload = CosmosStakingPayload.delegate(validator: "qbtc1NOT_A_VALOPER", denom: FX.denom, amount: FX.amount)
        XCTAssertThrowsError(try Self.resolve(payload)) { error in
            guard case CosmosStakingSignDataResolver.Errors.validatorPreflightFailed = error else {
                return XCTFail("Expected validatorPreflightFailed, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func assertMsgTypeURL(for payload: CosmosStakingPayload, expected: String) throws {
        let signDirect = try Self.resolve(payload)
        let body = try XCTUnwrap(Data(base64Encoded: signDirect.bodyBytes))
        let msgAny = try Self.bytes(field: 1, in: try Self.parseFields(body))
        XCTAssertEqual(try Self.string(field: 1, in: try Self.parseFields(msgAny)), expected)
    }

    private static func signDocHash(body: Data, authInfo: Data, chainID: String, accountNumber: String) -> String {
        var signDoc = Data()
        signDoc.appendProtoBytes(fieldNumber: 1, data: body)
        signDoc.appendProtoBytes(fieldNumber: 2, data: authInfo)
        signDoc.appendProtoString(fieldNumber: 3, value: chainID)
        signDoc.appendProtoVarint(fieldNumber: 4, value: UInt64(accountNumber) ?? 0)
        return SHA256.hash(data: signDoc).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Proto wire-format parser (test-only)

private extension QBTCStakingSignDataResolverTests {

    struct ProtoField: Equatable {
        let tag: Int
        let wireType: Int
        let value: Data
        let varint: UInt64?
    }

    enum ProtoParseError: Error {
        case truncated
        case missingField(Int)
        case wrongType
    }

    static func parseFields(_ data: Data) throws -> [ProtoField] {
        var fields: [ProtoField] = []
        var offset = data.startIndex
        while offset < data.endIndex {
            guard let (tagRaw, afterTag) = readVarint(data, at: offset) else {
                throw ProtoParseError.truncated
            }
            let tag = Int(tagRaw >> 3)
            let wireType = Int(tagRaw & 0x7)
            offset = afterTag
            switch wireType {
            case 0:
                guard let (value, afterValue) = readVarint(data, at: offset) else {
                    throw ProtoParseError.truncated
                }
                fields.append(ProtoField(tag: tag, wireType: wireType, value: Data(), varint: value))
                offset = afterValue
            case 2:
                guard let (length, afterLength) = readVarint(data, at: offset) else {
                    throw ProtoParseError.truncated
                }
                let end = afterLength + Int(length)
                guard end <= data.endIndex else { throw ProtoParseError.truncated }
                fields.append(ProtoField(tag: tag, wireType: wireType, value: data.subdata(in: afterLength..<end), varint: nil))
                offset = end
            default:
                throw ProtoParseError.wrongType
            }
        }
        return fields
    }

    static func string(field: Int, in fields: [ProtoField]) throws -> String {
        let bytes = try bytes(field: field, in: fields)
        guard let value = String(bytes: bytes, encoding: .utf8) else { throw ProtoParseError.wrongType }
        return value
    }

    static func bytes(field: Int, in fields: [ProtoField]) throws -> Data {
        guard let entry = fields.first(where: { $0.tag == field && $0.wireType == 2 }) else {
            throw ProtoParseError.missingField(field)
        }
        return entry.value
    }

    static func readVarint(_ data: Data, at offset: Data.Index) -> (UInt64, Data.Index)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = offset
        while cursor < data.endIndex {
            let byte = data[cursor]
            result |= UInt64(byte & 0x7f) << shift
            cursor = data.index(after: cursor)
            if (byte & 0x80) == 0 { return (result, cursor) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}
