//
//  CosmosStakingDisplayFeeTests.swift
//  VultisigAppTests
//
//  Pins the invariant that the DeFi-tab staking verify screen DISPLAYS the
//  exact fee the SignDoc SIGNS. The verify screen reads `SendTransaction.gas`
//  (via `gasInReadable` / `feesInReadable`); the SignDoc bakes
//  `feeAmount × msgCount` into AuthInfo. Before the fix the staking branch of
//  `FunctionTransactionScreen.onVerify` left gas at .zero, so the user saw
//  "0 QBTC / $0.00" while approving the real `feeAmount × N` — and the balance
//  preflight under-counted. These tests assert, for a single-msg flow AND a
//  multi-validator batched claim, that the gas the screen sets equals the fee
//  the resolver writes into the signed AuthInfo bytes, so display == signed
//  can never silently drift. The scaling arithmetic lives in one place
//  (`CosmosStakingConfig`) and is exercised from both sides here.
//

@testable import VultisigApp
import BigInt
import XCTest

final class CosmosStakingDisplayFeeTests: XCTestCase {

    // MARK: - Fixtures

    private enum FX {
        static let denom = "qbtc"
        static let amount = "100000000" // 1 QBTC at 8 decimals
        static let delegatorAddress = "qbtc1delegator00000000000000000000000000000"
        static let mldsaPubKeyHex = String(repeating: "ab", count: 1312)
        static let sequence: UInt64 = 42
    }

    private static let validValidator = Bech32TestUtils.makeValoperAddress(hrp: "qbtcvaloper")
    private static let validValidator2 = Bech32TestUtils.encodeBech32(
        hrp: "qbtcvaloper",
        payload: (0..<20).map { UInt8(($0 + 50) & 0xff) }
    )
    private static let validValidator3 = Bech32TestUtils.encodeBech32(
        hrp: "qbtcvaloper",
        payload: (0..<20).map { UInt8(($0 + 100) & 0xff) }
    )

    private static func makeChainSpecific() -> BlockChainSpecific {
        .Cosmos(accountNumber: 100, sequence: FX.sequence, gas: 7_500, transactionType: 0, ibcDenomTrace: nil)
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
        return Coin(asset: meta, address: FX.delegatorAddress, hexPublicKey: FX.mldsaPubKeyHex)
    }

    /// Reproduces what `FunctionTransactionScreen.onVerify` does for the
    /// staking branch: build the immutable tx (gas .zero) then set gas to the
    /// shared scaled-fee helper. This is the DISPLAYED value the verify screen
    /// renders and the balance preflight uses.
    private static func makeDisplayedTransaction(payload: CosmosStakingPayload) throws -> SendTransaction {
        let coin = makeQBTCCoin()
        let tx = SendTransaction(
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
        let scaledGas = try CosmosStakingConfig.scaledFeeAmountBigInt(
            for: coin.chain,
            msgCount: payload.msgCount
        )
        return tx.copy(gas: scaledGas)
    }

    /// The SIGNED fee — pulled straight out of the resolver's AuthInfo bytes
    /// (AuthInfo.fee.amount[0].amount), so it reflects exactly what is hashed
    /// and signed, with no shared intermediary the test could fool itself with.
    private static func signedFee(payload: CosmosStakingPayload) throws -> BigInt {
        let signDirect = try CosmosStakingSignDataResolver.resolveMLDSA(
            sendTransaction: makeDisplayedTransaction(payload: payload),
            chainSpecific: makeChainSpecific()
        )
        let authInfo = try XCTUnwrap(Data(base64Encoded: signDirect.authInfoBytes))
        let fee = try parseFields(try bytes(field: 2, in: try parseFields(authInfo)))
        let coin = try parseFields(try bytes(field: 1, in: fee))
        let amountString = try string(field: 2, in: coin)
        return try XCTUnwrap(BigInt(amountString))
    }

    private static func signedGasLimit(payload: CosmosStakingPayload) throws -> UInt64 {
        let signDirect = try CosmosStakingSignDataResolver.resolveMLDSA(
            sendTransaction: makeDisplayedTransaction(payload: payload),
            chainSpecific: makeChainSpecific()
        )
        let authInfo = try XCTUnwrap(Data(base64Encoded: signDirect.authInfoBytes))
        let fee = try parseFields(try bytes(field: 2, in: try parseFields(authInfo)))
        return try XCTUnwrap(varint(field: 2, in: fee))
    }

    // MARK: - msgCount matches the resolver's encoded-message count

    func testMsgCountIsOneForSingleMessageOps() {
        XCTAssertEqual(
            CosmosStakingPayload.delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount).msgCount,
            1
        )
        XCTAssertEqual(
            CosmosStakingPayload.undelegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount).msgCount,
            1
        )
        XCTAssertEqual(
            CosmosStakingPayload.redelegate(
                src: Self.validValidator2, dst: Self.validValidator3, denom: FX.denom, amount: FX.amount
            ).msgCount,
            1
        )
    }

    func testMsgCountEqualsValidatorCountForClaim() {
        let validators = [Self.validValidator, Self.validValidator2, Self.validValidator3]
        XCTAssertEqual(
            CosmosStakingPayload.withdrawRewards(validators: validators, denom: FX.denom).msgCount,
            validators.count
        )
    }

    // MARK: - display == signed (the bug)

    func testSingleMsgDisplayedFeeEqualsSignedFee() throws {
        let payload = CosmosStakingPayload.delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        let displayed = try Self.makeDisplayedTransaction(payload: payload)
        let signed = try Self.signedFee(payload: payload)

        // The exact bug: this was .zero before the fix.
        XCTAssertGreaterThan(displayed.gas, .zero, "Staking verify must not display a 0 fee")
        XCTAssertEqual(displayed.gas, signed, "Displayed gas must equal the signed fee")
        XCTAssertEqual(displayed.gas, BigInt(800), "QBTC single-msg fee is the 800 min_tx_fee floor")
    }

    func testMultiValidatorClaimDisplayedFeeEqualsSignedFee() throws {
        let validators = [Self.validValidator, Self.validValidator2, Self.validValidator3]
        let payload = CosmosStakingPayload.withdrawRewards(validators: validators, denom: FX.denom)
        let displayed = try Self.makeDisplayedTransaction(payload: payload)
        let signed = try Self.signedFee(payload: payload)

        XCTAssertEqual(displayed.gas, signed, "Displayed gas must equal the signed fee for an N-validator claim")
        // 800 × 3 — proves the display scales with msg count, not a hardcoded 1.
        XCTAssertEqual(displayed.gas, BigInt(800 * validators.count))
        XCTAssertNotEqual(displayed.gas, BigInt(800), "A 3-validator claim must not under-display the single-msg fee")
    }

    func testEightValidatorClaimDisplayedFeeEqualsSignedFee() throws {
        let validators = (0..<8).map { index in
            Bech32TestUtils.encodeBech32(
                hrp: "qbtcvaloper",
                payload: (0..<20).map { byte in UInt8((index * 13 + byte) & 0xff) }
            )
        }
        let payload = CosmosStakingPayload.withdrawRewards(validators: validators, denom: FX.denom)
        let displayed = try Self.makeDisplayedTransaction(payload: payload)
        let signed = try Self.signedFee(payload: payload)

        XCTAssertEqual(displayed.gas, signed)
        XCTAssertEqual(displayed.gas, BigInt(800 * 8))
    }

    // MARK: - readable string reflects the real fee (no longer "0 QBTC")

    func testSingleMsgGasInReadableShowsRealFee() throws {
        let payload = CosmosStakingPayload.delegate(validator: Self.validValidator, denom: FX.denom, amount: FX.amount)
        let displayed = try Self.makeDisplayedTransaction(payload: payload)
        let readable = displayed.gasInReadable

        XCTAssertTrue(readable.contains("QBTC"), "Fee row must show the QBTC ticker, got \(readable)")
        XCTAssertFalse(readable.hasPrefix("0 "), "Fee row must not read '0 QBTC', got \(readable)")
        // Parse locale-independently: strip ticker, normalise separator, compare value.
        let numeric = readable
            .replacingOccurrences(of: " QBTC", with: "")
            .replacingOccurrences(of: ",", with: ".")
        XCTAssertEqual(Decimal(string: numeric), Decimal(string: "0.000008"), "800 / 10^8 = 0.000008 QBTC")
    }

    // MARK: - shared scaling helper is the single source of truth

    func testScaledHelpersMatchManualMultiplication() throws {
        let entry = try CosmosStakingConfig.entry(for: .qbtc)
        for count in [1, 2, 3, 8] {
            XCTAssertEqual(
                try CosmosStakingConfig.scaledFeeAmount(for: .qbtc, msgCount: count),
                entry.feeAmount * UInt64(count)
            )
            XCTAssertEqual(
                try CosmosStakingConfig.scaledGasLimit(for: .qbtc, msgCount: count),
                entry.gasLimit * UInt64(count)
            )
        }
    }

    func testSignedGasLimitMatchesScaledHelperForClaim() throws {
        let validators = [Self.validValidator, Self.validValidator2, Self.validValidator3]
        let payload = CosmosStakingPayload.withdrawRewards(validators: validators, denom: FX.denom)
        let signedGas = try Self.signedGasLimit(payload: payload)
        XCTAssertEqual(
            signedGas,
            try CosmosStakingConfig.scaledGasLimit(for: .qbtc, msgCount: payload.msgCount)
        )
    }

    // MARK: - Terra display is fixed too (shared FunctionTransaction path)

    func testTerraSingleMsgDisplayFeeMatchesConfig() throws {
        let entry = try CosmosStakingConfig.entry(for: .terra)
        let scaled = try CosmosStakingConfig.scaledFeeAmountBigInt(for: .terra, msgCount: 1)
        XCTAssertEqual(scaled, BigInt(entry.feeAmount))
        XCTAssertGreaterThan(scaled, .zero, "Terra staking verify must not display a 0 fee either")
    }

    func testTerraClassicSingleMsgDisplayFeeMatchesConfig() throws {
        let entry = try CosmosStakingConfig.entry(for: .terraClassic)
        let scaled = try CosmosStakingConfig.scaledFeeAmountBigInt(for: .terraClassic, msgCount: 1)
        XCTAssertEqual(scaled, BigInt(entry.feeAmount))
        XCTAssertGreaterThan(scaled, .zero)
    }
}

// MARK: - Proto wire-format parser (test-only)

private extension CosmosStakingDisplayFeeTests {

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

    static func varint(field: Int, in fields: [ProtoField]) -> UInt64? {
        fields.first(where: { $0.tag == field && $0.wireType == 0 })?.varint
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
