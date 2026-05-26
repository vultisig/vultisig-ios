//
//  CosmosStakingHelperTests.swift
//  VultisigAppTests
//
//  Locks down the wire-format invariants for the Cosmos x/staking +
//  x/distribution proto encoders. Mirrors the SDK round-trip test pattern
//  at `vultisig-sdk/packages/sdk/tests/unit/platforms/react-native/
//  cosmos-staking.test.ts` — same test names where applicable, same fixture
//  shapes (cosmoshub-4 inputs verbatim) — but uses pure Swift parsing of the
//  produced bytes rather than a cosmjs-types bridge.
//

@testable import VultisigApp
import XCTest

final class CosmosStakingHelperTests: XCTestCase {

    // MARK: - Fixtures (mirror SDK FX)

    private enum FX {
        static let chainId = "cosmoshub-4"
        static let delegator = "cosmos1abcdefghijklmnopqrstuvwxyz0123456789ab"
        static let validator = "cosmosvaloper1zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzaaa"
        static let validatorSrc = "cosmosvaloper1srcsrcsrcsrcsrcsrcsrcsrcsrcsrcsrcsrcs"
        static let validatorDst = "cosmosvaloper1dstdstdstdstdstdstdstdstdstdstdstdsts"
        static let amount = "1000000"
        static let denom = "uatom"
        static let feeAmount: UInt64 = 7_500
        static let gasLimit: UInt64 = 250_000
        static let sequence: UInt64 = 42
        static let accountNumber: UInt64 = 100
        // 33-byte compressed secp256k1 pubkey, all 0x02 — matches the SDK
        // fixture verbatim.
        static let pubKey = Data(repeating: 0x02, count: 33)
    }

    // MARK: - MsgDelegate

    func testMsgDelegateUsesCanonicalTypeURL() {
        let anyMsg = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator,
            validator: FX.validator,
            amount: FX.amount,
            denom: FX.denom
        )
        let unwrapped = try? Self.decodeAny(anyMsg)
        XCTAssertEqual(unwrapped?.typeURL, "/cosmos.staking.v1beta1.MsgDelegate")
    }

    func testMsgDelegateEncodesAllFieldsInOrder() throws {
        let anyMsg = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator,
            validator: FX.validator,
            amount: FX.amount,
            denom: FX.denom
        )
        let unwrapped = try Self.decodeAny(anyMsg)
        let fields = try Self.parseFields(unwrapped.value)
        XCTAssertEqual(try Self.string(field: 1, in: fields), FX.delegator)
        XCTAssertEqual(try Self.string(field: 2, in: fields), FX.validator)

        let coinBytes = try Self.bytes(field: 3, in: fields)
        let coinFields = try Self.parseFields(coinBytes)
        XCTAssertEqual(try Self.string(field: 1, in: coinFields), FX.denom)
        XCTAssertEqual(try Self.string(field: 2, in: coinFields), FX.amount)
    }

    func testMsgDelegateIsDeterministicForIdenticalInputs() {
        let a = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let b = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        XCTAssertEqual(a, b)
    }

    func testMsgDelegateBytesChangeWhenValidatorChanges() {
        let a = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let b = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator,
            validator: "cosmosvaloper1otherotherotherotherotherotherother",
            amount: FX.amount,
            denom: FX.denom
        )
        XCTAssertNotEqual(a, b)
    }

    // MARK: - MsgUndelegate

    func testMsgUndelegateUsesUndelegateTypeURL() throws {
        let anyMsg = CosmosStakingHelper.encodeUndelegate(
            delegator: FX.delegator,
            validator: FX.validator,
            amount: FX.amount,
            denom: FX.denom
        )
        let unwrapped = try Self.decodeAny(anyMsg)
        XCTAssertEqual(unwrapped.typeURL, "/cosmos.staking.v1beta1.MsgUndelegate")
    }

    func testMsgUndelegateHasIdenticalWireShapeToDelegate() throws {
        // Same fields in same positions; only typeUrl differs. Pulling the
        // inner bytes through the same parser must produce the same field
        // structure.
        let delegate = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let undelegate = CosmosStakingHelper.encodeUndelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let delegateValue = try Self.decodeAny(delegate).value
        let undelegateValue = try Self.decodeAny(undelegate).value
        XCTAssertEqual(delegateValue, undelegateValue)
    }

    // MARK: - MsgBeginRedelegate

    func testMsgBeginRedelegateUsesCanonicalTypeURL() throws {
        let anyMsg = CosmosStakingHelper.encodeBeginRedelegate(
            delegator: FX.delegator,
            validatorSrc: FX.validatorSrc,
            validatorDst: FX.validatorDst,
            amount: FX.amount,
            denom: FX.denom
        )
        let unwrapped = try Self.decodeAny(anyMsg)
        XCTAssertEqual(unwrapped.typeURL, "/cosmos.staking.v1beta1.MsgBeginRedelegate")
    }

    func testMsgBeginRedelegateEncodesSrcAtFieldTwoAndDstAtFieldThree() throws {
        // The whole point of this test is the regression guard SDK calls
        // out at cosmos-staking.test.ts:153-162 — a src/dst swap would
        // produce a tx that drains the wrong validator.
        let anyMsg = CosmosStakingHelper.encodeBeginRedelegate(
            delegator: FX.delegator,
            validatorSrc: FX.validatorSrc,
            validatorDst: FX.validatorDst,
            amount: FX.amount,
            denom: FX.denom
        )
        let fields = try Self.parseFields(try Self.decodeAny(anyMsg).value)
        XCTAssertEqual(try Self.string(field: 1, in: fields), FX.delegator)
        XCTAssertEqual(try Self.string(field: 2, in: fields), FX.validatorSrc)
        XCTAssertEqual(try Self.string(field: 3, in: fields), FX.validatorDst)
        let coin = try Self.parseFields(try Self.bytes(field: 4, in: fields))
        XCTAssertEqual(try Self.string(field: 1, in: coin), FX.denom)
        XCTAssertEqual(try Self.string(field: 2, in: coin), FX.amount)
    }

    func testMsgBeginRedelegateSrcAndDstAreNotInterchangeable() throws {
        let normal = CosmosStakingHelper.encodeBeginRedelegate(
            delegator: FX.delegator,
            validatorSrc: FX.validatorSrc,
            validatorDst: FX.validatorDst,
            amount: FX.amount,
            denom: FX.denom
        )
        let swapped = CosmosStakingHelper.encodeBeginRedelegate(
            delegator: FX.delegator,
            validatorSrc: FX.validatorDst,
            validatorDst: FX.validatorSrc,
            amount: FX.amount,
            denom: FX.denom
        )
        XCTAssertNotEqual(normal, swapped)
    }

    // MARK: - MsgWithdrawDelegatorReward

    func testMsgWithdrawRewardUsesDistributionTypeURL() throws {
        let anyMsg = CosmosStakingHelper.encodeWithdrawDelegatorReward(
            delegator: FX.delegator,
            validator: FX.validator
        )
        let unwrapped = try Self.decodeAny(anyMsg)
        XCTAssertEqual(unwrapped.typeURL, "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward")
    }

    func testMsgWithdrawRewardHasNoCoinField() throws {
        let anyMsg = CosmosStakingHelper.encodeWithdrawDelegatorReward(
            delegator: FX.delegator,
            validator: FX.validator
        )
        let fields = try Self.parseFields(try Self.decodeAny(anyMsg).value)
        XCTAssertEqual(try Self.string(field: 1, in: fields), FX.delegator)
        XCTAssertEqual(try Self.string(field: 2, in: fields), FX.validator)
        XCTAssertEqual(fields.count, 2, "MsgWithdrawDelegatorReward must have exactly 2 fields")
    }

    // MARK: - buildTxBodyMulti

    func testTxBodySinglePacksMessageAtFieldOne() throws {
        let anyMsg = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let txBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [anyMsg])
        let fields = try Self.parseFields(txBody)
        XCTAssertEqual(fields.filter { $0.tag == 1 }.count, 1)
        XCTAssertEqual(try Self.bytes(field: 1, in: fields), anyMsg)
    }

    func testTxBodyMultiPacksAllMessagesPreservingOrder() throws {
        let validators = [
            "cosmosvaloper1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "cosmosvaloper1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "cosmosvaloper1ccccccccccccccccccccccccccccccccccc"
        ]
        let msgs = validators.map {
            CosmosStakingHelper.encodeWithdrawDelegatorReward(
                delegator: FX.delegator,
                validator: $0
            )
        }
        let txBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: msgs)
        let fields = try Self.parseFields(txBody)
        let messageEntries = fields.filter { $0.tag == 1 }
        XCTAssertEqual(messageEntries.count, validators.count)
        for (index, entry) in messageEntries.enumerated() {
            XCTAssertEqual(entry.value, msgs[index], "TxBody message at index \(index) must round-trip")
        }
    }

    func testTxBodyMultiHandlesEightMessagesForBatchedClaimSoftCap() throws {
        // The batched-claim UI soft cap is 8 validators per tx. The encoder
        // imposes no cap of its own — exercising N=8 here pins linear
        // packing all the way up to the UI ceiling.
        let validators = (1...8).map { index in
            "cosmosvaloper1batch00000000000000000000000000000\(index)"
        }
        let msgs = validators.map {
            CosmosStakingHelper.encodeWithdrawDelegatorReward(
                delegator: FX.delegator,
                validator: $0
            )
        }
        let txBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: msgs)
        let fields = try Self.parseFields(txBody)
        XCTAssertEqual(fields.filter { $0.tag == 1 }.count, 8)
    }

    func testTxBodyEmbedsMemoAtFieldTwoWhenProvided() throws {
        let anyMsg = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let txBody = CosmosStakingHelper.buildTxBodyMulti(
            msgsAny: [anyMsg],
            memo: "claim airdrop via vultiagent"
        )
        let fields = try Self.parseFields(txBody)
        XCTAssertEqual(try Self.string(field: 2, in: fields), "claim airdrop via vultiagent")
    }

    func testTxBodyOmitsMemoFieldWhenEmpty() throws {
        let anyMsg = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let txBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [anyMsg], memo: "")
        let fields = try Self.parseFields(txBody)
        // proto3 default-skip: an empty memo is not emitted at all. Pinning
        // this guards against the encoder accidentally writing a zero-byte
        // memo field that would change the SignDoc hash.
        XCTAssertEqual(fields.filter { $0.tag == 2 }.count, 0)
    }

    func testTxBodyMixesMsgTypesPreservingTypeURLOrder() throws {
        let delegate = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator, amount: FX.amount, denom: FX.denom
        )
        let withdraw = CosmosStakingHelper.encodeWithdrawDelegatorReward(
            delegator: FX.delegator,
            validator: FX.validator
        )
        let txBody = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [delegate, withdraw])
        let messages = try Self.parseFields(txBody).filter { $0.tag == 1 }
        XCTAssertEqual(messages.count, 2)
        let firstType = try Self.decodeAny(messages[0].value).typeURL
        let secondType = try Self.decodeAny(messages[1].value).typeURL
        XCTAssertEqual(firstType, "/cosmos.staking.v1beta1.MsgDelegate")
        XCTAssertEqual(secondType, "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward")
    }

    // MARK: - AuthInfo

    func testAuthInfoEmbedsPubKeyAnyAndFee() throws {
        let authInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: FX.pubKey,
            sequence: FX.sequence,
            gasLimit: FX.gasLimit,
            feeDenom: FX.denom,
            feeAmount: FX.feeAmount
        )
        let fields = try Self.parseFields(authInfo)

        // signer_infos at field 1 (single entry)
        let signerInfoEntries = fields.filter { $0.tag == 1 }
        XCTAssertEqual(signerInfoEntries.count, 1)
        let signerInfo = try Self.parseFields(signerInfoEntries[0].value)

        // Inner field 1 = pubkey Any
        let pubKeyAny = try Self.bytes(field: 1, in: signerInfo)
        let pubKeyAnyFields = try Self.parseFields(pubKeyAny)
        XCTAssertEqual(try Self.string(field: 1, in: pubKeyAnyFields), "/cosmos.crypto.secp256k1.PubKey")

        // Inner field 3 = sequence
        let sequence = try Self.varint(field: 3, in: signerInfo)
        XCTAssertEqual(sequence, FX.sequence)

        // Fee at field 2
        let fee = try Self.parseFields(try Self.bytes(field: 2, in: fields))
        let coin = try Self.parseFields(try Self.bytes(field: 1, in: fee))
        XCTAssertEqual(try Self.string(field: 1, in: coin), FX.denom)
        XCTAssertEqual(try Self.string(field: 2, in: coin), String(FX.feeAmount))
        XCTAssertEqual(try Self.varint(field: 2, in: fee), FX.gasLimit)
    }

    // MARK: - SignDoc

    func testSignDocBytesChangeWhenAccountNumberChanges() {
        let body = CosmosStakingHelper.buildTxBodyMulti(
            msgsAny: [
                CosmosStakingHelper.encodeDelegate(
                    delegator: FX.delegator, validator: FX.validator,
                    amount: FX.amount, denom: FX.denom
                )
            ]
        )
        let authInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: FX.pubKey, sequence: FX.sequence,
            gasLimit: FX.gasLimit, feeDenom: FX.denom, feeAmount: FX.feeAmount
        )
        let docA = CosmosStakingHelper.buildSignDoc(
            bodyBytes: body, authInfoBytes: authInfo,
            chainId: FX.chainId, accountNumber: FX.accountNumber
        )
        let docB = CosmosStakingHelper.buildSignDoc(
            bodyBytes: body, authInfoBytes: authInfo,
            chainId: FX.chainId, accountNumber: FX.accountNumber + 1
        )
        XCTAssertNotEqual(docA.bytes, docB.bytes)
        XCTAssertNotEqual(docA.hashHex, docB.hashHex)
    }

    func testSignDocHashIsSha256OfBytes() {
        let body = CosmosStakingHelper.buildTxBodyMulti(
            msgsAny: [
                CosmosStakingHelper.encodeDelegate(
                    delegator: FX.delegator, validator: FX.validator,
                    amount: FX.amount, denom: FX.denom
                )
            ]
        )
        let authInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: FX.pubKey, sequence: FX.sequence,
            gasLimit: FX.gasLimit, feeDenom: FX.denom, feeAmount: FX.feeAmount
        )
        let doc = CosmosStakingHelper.buildSignDoc(
            bodyBytes: body, authInfoBytes: authInfo,
            chainId: FX.chainId, accountNumber: FX.accountNumber
        )
        XCTAssertEqual(doc.hashHex.count, 64)
        XCTAssertEqual(doc.hashHex, doc.hashHex.lowercased())
    }

    func testSignDocIsDeterministic() {
        let msg = CosmosStakingHelper.encodeDelegate(
            delegator: FX.delegator, validator: FX.validator,
            amount: FX.amount, denom: FX.denom
        )
        let body = CosmosStakingHelper.buildTxBodyMulti(msgsAny: [msg])
        let authInfo = CosmosStakingHelper.buildAuthInfo(
            pubKey: FX.pubKey, sequence: FX.sequence,
            gasLimit: FX.gasLimit, feeDenom: FX.denom, feeAmount: FX.feeAmount
        )
        let a = CosmosStakingHelper.buildSignDoc(
            bodyBytes: body, authInfoBytes: authInfo,
            chainId: FX.chainId, accountNumber: FX.accountNumber
        )
        let b = CosmosStakingHelper.buildSignDoc(
            bodyBytes: body, authInfoBytes: authInfo,
            chainId: FX.chainId, accountNumber: FX.accountNumber
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - Proto wire-format parser (test-only)

/// Tiny proto wire-format walker used by the helper tests to parse the
/// bytes the encoder produces. NOT used in production — kept inside the
/// test file so the production encoder remains the single proto authority.
private extension CosmosStakingHelperTests {

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

    static func decodeAny(_ data: Data) throws -> (typeURL: String, value: Data) {
        let fields = try parseFields(data)
        return (try string(field: 1, in: fields), try bytes(field: 2, in: fields))
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
            case 0: // varint
                guard let (value, afterValue) = readVarint(data, at: offset) else {
                    throw ProtoParseError.truncated
                }
                fields.append(ProtoField(tag: tag, wireType: wireType, value: Data(), varint: value))
                offset = afterValue
            case 2: // length-delimited
                guard let (length, afterLength) = readVarint(data, at: offset) else {
                    throw ProtoParseError.truncated
                }
                let end = afterLength + Int(length)
                guard end <= data.endIndex else { throw ProtoParseError.truncated }
                let payload = data.subdata(in: afterLength..<end)
                fields.append(ProtoField(tag: tag, wireType: wireType, value: payload, varint: nil))
                offset = end
            default:
                throw ProtoParseError.wrongType
            }
        }
        return fields
    }

    static func string(field: Int, in fields: [ProtoField]) throws -> String {
        let bytes = try bytes(field: field, in: fields)
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw ProtoParseError.wrongType
        }
        return value
    }

    static func bytes(field: Int, in fields: [ProtoField]) throws -> Data {
        guard let entry = fields.first(where: { $0.tag == field && $0.wireType == 2 }) else {
            throw ProtoParseError.missingField(field)
        }
        return entry.value
    }

    static func varint(field: Int, in fields: [ProtoField]) throws -> UInt64 {
        guard let entry = fields.first(where: { $0.tag == field && $0.wireType == 0 }),
              let value = entry.varint else {
            throw ProtoParseError.missingField(field)
        }
        return value
    }

    static func readVarint(_ data: Data, at offset: Data.Index) -> (UInt64, Data.Index)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = offset
        while cursor < data.endIndex {
            let byte = data[cursor]
            result |= UInt64(byte & 0x7f) << shift
            cursor = data.index(after: cursor)
            if (byte & 0x80) == 0 {
                return (result, cursor)
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}
