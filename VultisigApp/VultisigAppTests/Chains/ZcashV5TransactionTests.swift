//
//  ZcashV5TransactionTests.swift
//  VultisigAppTests
//
//  Zcash v5 (ZIP-225 / ZIP-244) signing through the production entry points.
//  Expected sighashes, DER signatures, raw bytes and txids come from
//  `Fixtures/ZcashV5Golden.json` and from the same reference implementation,
//  which reproduces real mainnet v5 transactions; none are derived from this
//  module's output.
//

import BigInt
import Tss
import WalletCore
import XCTest
@testable import VultisigApp

final class ZcashV5TransactionTests: XCTestCase {

    // MARK: - Golden fixtures

    func testFixtureSighashesMatchInInputOrder() throws {
        for fixture in try Self.loadFixtures() {
            let hashes = try ZcashV5Transaction.preImageHashes(inputData: fixture.signingInput().serializedData())
            XCTAssertEqual(hashes.map(\.hexString), fixture.expected.sighashes, fixture.name)
        }
    }

    func testFixturesSignAndCompileThroughUTXOChainsHelper() throws {
        for fixture in try Self.loadFixtures() {
            let inputData = try fixture.signingInput().serializedData()
            let key = try XCTUnwrap(PrivateKey(data: XCTUnwrap(Data(hexString: fixture.privateKey))))
            let derSignatures = try ZcashV5Transaction.preImageHashes(inputData: inputData)
                .map { try XCTUnwrap(key.signAsDER(digest: $0)).hexString }
            XCTAssertEqual(derSignatures, fixture.expected.derSignatures, fixture.name)

            let signed = try UTXOChainsHelper(coin: .zcash).getSignedTransaction(
                coinHexPublicKey: fixture.publicKey,
                inputData: inputData,
                signatures: Self.responses(hashes: fixture.expected.sighashes, derSignatures: fixture.expected.derSignatures)
            )
            XCTAssertEqual(signed.rawTransaction, fixture.expected.raw, fixture.name)
            XCTAssertEqual(signed.transactionHash, fixture.expected.txid, fixture.name)
        }
    }

    func testNativeSendEntryPointsReproduceTheOneInputFixture() throws {
        let fixture = try Self.fixture(named: "one_input_with_change_nu63")
        let payload = Self.payload(
            fixture: fixture,
            amount: fixture.plan.amount,
            utxos: fixture.utxoInfos,
            branchId: fixture.walletCoreBranchIdLittleEndian
        )
        let helper = UTXOChainsHelper(coin: .zcash)

        // WalletCore planning is unchanged; this pins that it plans the fixture's shape.
        let plan = try BitcoinSigningInput(serializedBytes: helper.getBitcoinPreSigningInputData(keysignPayload: payload)).plan
        XCTAssertEqual(plan.amount, fixture.plan.amount)
        XCTAssertEqual(plan.change, fixture.plan.change)

        XCTAssertEqual(try helper.getPreSignedImageHash(keysignPayload: payload), fixture.expected.sighashes)
        let signed = try helper.getSignedTransaction(
            keysignPayload: payload,
            signatures: Self.responses(hashes: fixture.expected.sighashes, derSignatures: fixture.expected.derSignatures)
        )
        XCTAssertEqual(signed.rawTransaction, fixture.expected.raw)
        XCTAssertEqual(signed.transactionHash, fixture.expected.txid)
    }

    /// Two-input THORChain ZEC swap with an OP_RETURN memo. WalletCore plans it
    /// (inputs ordered 300k then 400k, 25,296 zat fee); the expected values
    /// are the reference implementation's output for that plan, signed with the
    /// fixture key. Input-order sighashes are deliberately not sorted, so the
    /// swap arm (input order) and the send entry point (sorted) differ.
    private static let memoSwapExpected = (
        sighashes: [
            "97349ed6adf42bfbb556c0b3ac5c56a2cc1f5255e35bba53a34679c4a2fd9ced",
            "7a38468cd418b3b09430e47047c86825743051f6a2b7adccd9fec1f79dc191c3"
        ],
        derSignatures: [
            "3045022100cf244f95c9cb29c36425c01d3f134481487fd3473f3db6aa61100d01690299df022058cd21e6a680582a3338bc3bea192cefc4454395357559020fe8da5dac87f606",
            "304402205c74dfe3e033020556b99f5f41d719e243a1f5bbd8fe4ba3f3c2062740f4604a0220119daf4f285501ed76df43b061278c6f48b42318539798bbe9c0985ed5ccd770"
        ],
        txid: "158c9b248d58e12b4a31744bf10b687e5c51f18401c00cc2b66930048d204233",
        raw: "050000800a27a726d90a19770000000000000000026666666666666666666666666666666666666666666666666666d5d4d3d2d1d0000000006b483045022100cf244f95c9cb29c36425c01d3f134481487fd3473f3db6aa61100d01690299df022058cd21e6a680582a3338bc3bea192cefc4454395357559020fe8da5dac87f6060121034f355bdcb7cc0af728ef3cceb9615d90684bb5b2ca5f859ab0f0b704075871aaffffffff5555555555555555555555555555555555555555555555555555c5c4c3c2c1c0030000006a47304402205c74dfe3e033020556b99f5f41d719e243a1f5bbd8fe4ba3f3c2062740f4604a0220119daf4f285501ed76df43b061278c6f48b42318539798bbe9c0985ed5ccd7700121034f355bdcb7cc0af728ef3cceb9615d90684bb5b2ca5f859ab0f0b704075871aaffffffff0320a10700000000001976a914531260aa2a199e228c537dfa42c82bea2c7c1f4d88ac70aa0200000000001976a914fc7250a211deddc70ee5a2738de5f07817351cef88ac0000000000000000426a403d3a4554482e4554483a3078383664353236643636323441624330313738634637323936634435333845636330383041393546313a302f312f303a76693a3530000000"
    )

    func testThorchainSwapArmReturnsInputOrderSighashesAndCompiles() throws {
        let fixture = try Self.fixture(named: "two_inputs_change_memo_nu7")
        let swap = Self.swapPayload(fixture: fixture)
        let swaps = THORChainSwaps()

        let plan = try BitcoinSigningInput(serializedBytes: swaps.getPreSignedInputData(
            swapPayload: swap.swapPayload,
            keysignPayload: swap.keysignPayload,
            nonceOffset: 0
        )).plan
        XCTAssertEqual(plan.utxos.map(\.amount), [300_000, 400_000])
        XCTAssertEqual(plan.change, 174_704)

        let expected = Self.memoSwapExpected
        XCTAssertNotEqual(expected.sighashes, expected.sighashes.sorted())
        XCTAssertEqual(
            try swaps.getPreSignedImageHash(swapPayload: swap.swapPayload, keysignPayload: swap.keysignPayload, nonceOffset: 0),
            expected.sighashes
        )

        let signed = try swaps.getSignedTransaction(
            swapPayload: swap.swapPayload,
            keysignPayload: swap.keysignPayload,
            signatures: Self.responses(hashes: expected.sighashes, derSignatures: expected.derSignatures),
            nonceOffset: 0
        )
        XCTAssertEqual(signed.rawTransaction, expected.raw)
        XCTAssertEqual(signed.transactionHash, expected.txid)
    }

    func testSendEntryPointReturnsSortedSighashesForTheSameMemoTransaction() throws {
        let fixture = try Self.fixture(named: "two_inputs_change_memo_nu7")
        let payload = Self.payload(
            fixture: fixture,
            amount: 500_000,
            utxos: Self.swapUtxos,
            branchId: fixture.walletCoreBranchIdLittleEndian,
            memo: fixture.plan.memo
        )
        let helper = UTXOChainsHelper(coin: .zcash)
        let expected = Self.memoSwapExpected

        XCTAssertEqual(try helper.getPreSignedImageHash(keysignPayload: payload), expected.sighashes.sorted())
        let signed = try helper.getSignedTransaction(
            keysignPayload: payload,
            signatures: Self.responses(hashes: expected.sighashes, derSignatures: expected.derSignatures)
        )
        XCTAssertEqual(signed.rawTransaction, expected.raw)
        XCTAssertEqual(signed.transactionHash, expected.txid)
    }

    // MARK: - Fail-closed guards (each test goes green only while its guard exists)

    // Mutation: drop the 4-byte branch id check.
    func testSendEntryPointRejectsABranchIdThatIsNotFourBytes() throws {
        let fixture = try Self.fixture(named: "one_input_with_change_nu63")
        let payload = Self.payload(
            fixture: fixture,
            amount: fixture.plan.amount,
            utxos: fixture.utxoInfos,
            branchId: "5b16a5"
        )
        XCTAssertThrowsError(try UTXOChainsHelper(coin: .zcash).getPreSignedImageHash(keysignPayload: payload)) {
            XCTAssertEqual($0 as? ZcashV5TransactionError, .invalidBranchId(byteCount: 3))
        }
    }

    // Mutation: drop the memo length check (or relax it past 80).
    func testSendEntryPointRejectsAMemoOverEightyBytes() throws {
        let fixture = try Self.fixture(named: "one_input_with_change_nu63")
        func hashes(memoLength: Int) throws -> [String] {
            try UTXOChainsHelper(coin: .zcash).getPreSignedImageHash(keysignPayload: Self.payload(
                fixture: fixture,
                amount: fixture.plan.amount,
                utxos: fixture.utxoInfos,
                branchId: fixture.walletCoreBranchIdLittleEndian,
                memo: String(repeating: "m", count: memoLength)
            ))
        }
        XCTAssertEqual(try hashes(memoLength: 80).count, 1)
        XCTAssertThrowsError(try hashes(memoLength: 81)) {
            XCTAssertEqual($0 as? ZcashV5TransactionError, .memoTooLong(byteCount: 81))
        }
    }

    // Mutation: drop the P2PKH input script check.
    func testRejectsAnInputThatIsNotP2PKH() throws {
        var input = try Self.fixture(named: "two_inputs_change_memo_nu7").signingInput()
        input.plan.utxos[1].script = try XCTUnwrap(Data(hexString: "a914fc7250a211deddc70ee5a2738de5f07817351cef87"))
        XCTAssertThrowsError(try ZcashV5Transaction.preImageHashes(inputData: input.serializedData())) {
            XCTAssertEqual($0 as? ZcashV5TransactionError, .nonP2PKHInput(index: 1))
        }
    }

    // Mutation: drop the empty-plan check.
    func testRejectsAPlanWithoutInputs() throws {
        var input = try Self.fixture(named: "one_input_with_change_nu63").signingInput()
        input.plan.utxos = []
        XCTAssertThrowsError(try ZcashV5Transaction.preImageHashes(inputData: input.serializedData())) {
            XCTAssertEqual($0 as? ZcashV5TransactionError, .noInputs)
        }
    }

    // Mutation: drop the empty lock script check (the output would pay an empty script).
    func testRejectsAnOutputAddressWithoutALockScript() throws {
        var input = try Self.fixture(named: "one_input_with_change_nu63").signingInput()
        input.toAddress = "t1NotAZcashAddress"
        XCTAssertThrowsError(try ZcashV5Transaction.preImageHashes(inputData: input.serializedData())) {
            XCTAssertEqual($0 as? ZcashV5TransactionError, .invalidOutputAddress("t1NotAZcashAddress"))
        }
    }

    // Mutation: drop the verifyAsDER check in compile.
    func testCompileRejectsASignatureOverADifferentHash() throws {
        let fixture = try Self.fixture(named: "one_input_with_change_nu63")
        let otherSignature = try Self.fixture(named: "one_input_no_change_nu7").expected.derSignatures
        try assertCompileRejected(fixture, signatures: Self.responses(hashes: fixture.expected.sighashes, derSignatures: otherSignature))
    }

    // Mutation: drop the verifyAsDER check in compile (a missing signature reads as empty DER).
    func testCompileRejectsAMissingSignature() throws {
        try assertCompileRejected(Self.fixture(named: "one_input_with_change_nu63"), signatures: [:])
    }

    private func assertCompileRejected(_ fixture: Fixture, signatures: [String: TssKeysignResponse]) throws {
        let inputData = try fixture.signingInput().serializedData()
        let expectedReason = try XCTUnwrap(ZcashV5TransactionError.invalidSignature(inputIndex: 0).errorDescription)
        XCTAssertThrowsError(try UTXOChainsHelper(coin: .zcash).getSignedTransaction(
            coinHexPublicKey: fixture.publicKey,
            inputData: inputData,
            signatures: signatures
        )) {
            XCTAssertTrue("\($0)".contains(expectedReason), "\($0)")
        }
    }

    // MARK: - Fixtures and payloads

    private static let swapUtxos = [
        UtxoInfo(hash: "c0c1c2c3c4c5" + String(repeating: "55", count: 26), amount: 400_000, index: 3),
        UtxoInfo(hash: "d0d1d2d3d4d5" + String(repeating: "66", count: 26), amount: 300_000, index: 0)
    ]

    private struct GoldenFile: Decodable {
        let fixtures: [Fixture]
    }

    private struct Fixture: Decodable {
        struct Plan: Decodable {
            let amount: Int64
            let change: Int64
            let memo: String?
            let utxos: [Utxo]
        }

        struct Utxo: Decodable {
            let txid: String
            let vout: UInt32
            let amount: Int64
            let script: String
            let sequence: UInt32
        }

        struct Expected: Decodable {
            let sighashes: [String]
            let derSignatures: [String]
            let txid: String
            let raw: String
        }

        let name: String
        let walletCoreBranchIdLittleEndian: String
        let privateKey: String
        let publicKey: String
        let fromAddress: String
        let toAddress: String
        let plan: Plan
        let expected: Expected

        var utxoInfos: [UtxoInfo] {
            plan.utxos.map { UtxoInfo(hash: $0.txid, amount: $0.amount, index: $0.vout) }
        }

        /// The `SigningInput` the UTXO helper hands to the signer: plan, addresses, branch id, memo.
        func signingInput() throws -> BitcoinSigningInput {
            let branchId = try XCTUnwrap(Data(hexString: walletCoreBranchIdLittleEndian))
            let utxos = try plan.utxos.map { utxo in
                let script = try XCTUnwrap(Data(hexString: utxo.script))
                return BitcoinUnspentTransaction.with {
                    $0.outPoint = BitcoinOutPoint.with {
                        $0.hash = Data.reverse(hexString: utxo.txid)
                        $0.index = utxo.vout
                        $0.sequence = utxo.sequence
                    }
                    $0.amount = utxo.amount
                    $0.script = script
                }
            }
            return BitcoinSigningInput.with {
                $0.coinType = CoinType.zcash.rawValue
                $0.toAddress = toAddress
                $0.changeAddress = fromAddress
                $0.lockTime = 0
                $0.plan = BitcoinTransactionPlan.with {
                    $0.amount = plan.amount
                    $0.change = plan.change
                    $0.branchID = branchId
                    $0.outputOpReturn = Data((plan.memo ?? "").utf8)
                    $0.utxos = utxos
                }
            }
        }
    }

    private static func loadFixtures() throws -> [Fixture] {
        let url = try XCTUnwrap(Bundle(for: ZcashV5TransactionTests.self).url(forResource: "ZcashV5Golden", withExtension: "json"))
        return try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url)).fixtures
    }

    private static func fixture(named name: String) throws -> Fixture {
        try XCTUnwrap(loadFixtures().first { $0.name == name })
    }

    private static func responses(hashes: [String], derSignatures: [String]) -> [String: TssKeysignResponse] {
        Dictionary(uniqueKeysWithValues: zip(hashes, derSignatures).map { hash, der in
            let response = TssKeysignResponse()
            response.msg = hash
            response.derSignature = der
            return (hash, response)
        })
    }

    private static func coin(_ fixture: Fixture) -> Coin {
        let meta = CoinMeta.make(chain: .zcash, ticker: "ZEC", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: fixture.fromAddress, hexPublicKey: fixture.publicKey)
    }

    private static func payload(
        fixture: Fixture,
        amount: Int64,
        utxos: [UtxoInfo],
        branchId: String,
        memo: String? = nil,
        swapPayload: SwapPayload? = nil
    ) -> KeysignPayload {
        SigningGoldenFactory.payload(
            coin: coin(fixture),
            toAddress: fixture.toAddress,
            toAmount: BigInt(amount),
            chainSpecific: .UTXO(byteFee: 100, sendMaxAmount: false, zcashBranchId: branchId),
            utxos: utxos,
            memo: memo,
            swapPayload: swapPayload
        )
    }

    /// A THORChain ZEC swap paying the fixture's `toAddress` as the inbound vault, memo in OP_RETURN.
    private static func swapPayload(fixture: Fixture) -> (swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload) {
        let swapPayload = THORChainSwapPayload(
            fromAddress: fixture.fromAddress,
            fromCoin: coin(fixture),
            toCoin: coin(fixture),
            vaultAddress: fixture.toAddress,
            routerAddress: nil,
            fromAmount: BigInt(500_000),
            toAmountDecimal: 0,
            toAmountLimit: "0",
            streamingInterval: "1",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
        let keysignPayload = payload(
            fixture: fixture,
            amount: 500_000,
            utxos: swapUtxos,
            branchId: fixture.walletCoreBranchIdLittleEndian,
            memo: fixture.plan.memo,
            swapPayload: .thorchain(swapPayload)
        )
        return (swapPayload, keysignPayload)
    }
}
