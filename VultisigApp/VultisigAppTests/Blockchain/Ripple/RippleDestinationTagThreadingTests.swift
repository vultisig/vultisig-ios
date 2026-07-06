//
//  RippleDestinationTagThreadingTests.swift
//  VultisigAppTests
//
//  Pins the XRP destination-tag wire contract end to end:
//  - `RippleDestinationTag.parseCanonical` accepts only canonical uint32
//    decimals (the SDK co-signer's round-trip parse is strict, so leading
//    zeros or whitespace would split the committee's pre-image hashes);
//  - `RippleHelper.getPreSignedInputData` rejects any XRP payload whose memo
//    slot isn't empty-or-canonical — on both sides of the ceremony — and
//    builds a real wallet-core `destinationTag`, never an on-chain Memos blob;
//  - the send form resolves the dedicated tag field against the legacy
//    numeric-memo workaround and threads the result into `SendTransaction`
//    and the keysign payload memo slot.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

final class RippleDestinationTagThreadingTests: XCTestCase {

    // MARK: - Canonical parse

    func testParseCanonicalAcceptsBounds() {
        XCTAssertEqual(RippleDestinationTag.parseCanonical("0"), 0)
        XCTAssertEqual(RippleDestinationTag.parseCanonical("1"), 1)
        XCTAssertEqual(RippleDestinationTag.parseCanonical("12345"), 12345)
        XCTAssertEqual(RippleDestinationTag.parseCanonical("4294967295"), UInt32.max)
    }

    func testParseTagRejectsZero() {
        // Wallet-core's proto3 scalar can't express "present with value 0" —
        // a zero tag would sign as an UNTAGGED payment while the UI showed a
        // tag. The contract rejects it loudly instead.
        XCTAssertNil(RippleDestinationTag.parseTag("0"))
        XCTAssertEqual(RippleDestinationTag.parseTag("1"), 1)
        XCTAssertEqual(RippleDestinationTag.parseTag("4294967295"), UInt32.max)
    }

    func testParseCanonicalRejectsNonCanonical() {
        let rejected = [
            "4294967296",   // > uint32 max
            "0123",         // leading zero
            "00",           // leading zero
            " 12",          // leading whitespace
            "12 ",          // trailing whitespace
            "+12",          // sign
            "-1",           // sign
            "1.5",          // not an integer
            "1e3",          // not decimal digits
            "tag:123",      // text
            ""              // empty
        ]
        for input in rejected {
            XCTAssertNil(RippleDestinationTag.parseCanonical(input), "expected rejection for \"\(input)\"")
        }
    }

    // MARK: - Payload memo contract

    func testValidatePayloadMemoAcceptsEmptyAndCanonical() throws {
        XCTAssertNil(try RippleDestinationTag.validatePayloadMemo(nil))
        XCTAssertNil(try RippleDestinationTag.validatePayloadMemo(""))
        XCTAssertEqual(try RippleDestinationTag.validatePayloadMemo("12345"), 12345)
        XCTAssertEqual(try RippleDestinationTag.validatePayloadMemo("4294967295"), UInt32.max)
    }

    func testValidatePayloadMemoRejectsTextAndNonCanonical() {
        for memo in ["hello", "tag:12345", "0123", " 12345", "4294967296", "0"] {
            XCTAssertThrowsError(try RippleDestinationTag.validatePayloadMemo(memo), "expected rejection for \"\(memo)\"") { error in
                XCTAssertEqual(error as? RippleMemoError, .invalidMemo(memo))
            }
        }
    }

    // MARK: - Signing input

    func testCanonicalMemoBecomesWalletCoreDestinationTag() throws {
        let payload = Self.makeRipplePayload(memo: "12345")
        let inputData = try RippleHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try RippleSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.opPayment.destinationTag, 12345)
        XCTAssertTrue(input.rawJson.isEmpty, "tagged payments must never take the rawJson path")
        XCTAssertEqual(input.opPayment.destination, Self.destination)
    }

    func testEmptyMemoBuildsPlainPayment() throws {
        let payload = Self.makeRipplePayload(memo: nil)
        let inputData = try RippleHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try RippleSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.opPayment.destinationTag, 0, "proto default — no tag set")
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    func testTextMemoRejectsPayload() {
        // Pre-change this silently became an on-chain Memos blob with NO
        // destination tag — the uncredited-exchange-deposit shape.
        for memo in ["tag:12345", "hello", "12345 ", "0123"] {
            let payload = Self.makeRipplePayload(memo: memo)
            XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload), "expected rejection for \"\(memo)\"") { error in
                XCTAssertEqual(error as? RippleMemoError, .invalidMemo(memo))
            }
        }
    }

    func testTagAboveU32MaxRejectsPayload() {
        // Pre-change a 2^32..2^64 memo parsed as UInt64 and reached
        // wallet-core, which failed the ceremony with a cryptic u32 error.
        let payload = Self.makeRipplePayload(memo: "4294967296")
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload))
    }

    // MARK: - Swap payloads keep the legacy memo contract

    func testSwapPayloadNumericMemoStillBecomesDestinationTag() throws {
        // The SwapKit XRP contract: resolved tag stringified into the memo.
        let payload = Self.makeRipplePayload(memo: "54321", withSwapPayload: true)
        let inputData = try RippleHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try RippleSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.opPayment.destinationTag, 54321)
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    func testSwapPayloadTextMemoStillTakesMemosPath() throws {
        // THORChain-family swaps route via a text memo the protocol reads
        // on-chain — the strict destination-tag contract must not apply.
        let payload = Self.makeRipplePayload(memo: "=:ETH.ETH:0x1234:0/1/0", withSwapPayload: true)
        let inputData = try RippleHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try RippleSigningInput(serializedBytes: inputData)

        XCTAssertFalse(input.rawJson.isEmpty, "swap text memo must ride the on-chain Memos blob")
        XCTAssertTrue(input.rawJson.contains("Memos"))
        XCTAssertEqual(input.opPayment.destinationTag, 0)
    }

    func testPreimageHashMatchesLegacyNumericMemoPayload() throws {
        // Byte-parity pin: a payload whose memo slot carries the canonical
        // tag hashes identically however the tag was sourced (dedicated
        // field or legacy numeric memo) — the wire format did not move.
        let fromTagField = Self.makeRipplePayload(memo: "999")
        let legacyNumericMemo = Self.makeRipplePayload(memo: "999")

        let lhs = try RippleHelper.getPreSignedImageHash(keysignPayload: fromTagField)
        let rhs = try RippleHelper.getPreSignedImageHash(keysignPayload: legacyNumericMemo)

        XCTAssertFalse(lhs.isEmpty)
        XCTAssertEqual(lhs, rhs)
    }

    // MARK: - Verify seam (SendTransaction → payload memo)

    @MainActor
    func testPayloadMemoEncodesTagAsCanonicalDecimal() {
        let tx = Self.makeSendTransaction(memo: "", destinationTag: 12345)
        XCTAssertEqual(SendCryptoVerifyLogic.payloadMemo(tx: tx), "12345")
    }

    @MainActor
    func testPayloadMemoNilWhenNoTagAndNoMemo() {
        let tx = Self.makeSendTransaction(memo: "", destinationTag: nil)
        XCTAssertNil(SendCryptoVerifyLogic.payloadMemo(tx: tx))
    }

    @MainActor
    func testPayloadMemoTagWinsOverMemoText() {
        // Belt-and-braces: the form blocks this combination, but if a tag is
        // present it owns the memo slot.
        let tx = Self.makeSendTransaction(memo: "12345", destinationTag: 12345)
        XCTAssertEqual(SendCryptoVerifyLogic.payloadMemo(tx: tx), "12345")
    }

    // MARK: - Form seam (SendDetailsViewModel)

    @MainActor
    func testRippleTagFieldThreadsIntoTransaction() throws {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "12345"

        XCTAssertTrue(vm.validateRippleTagAndMemo())
        let tx = try vm.makeTransaction()
        XCTAssertEqual(tx.destinationTag, 12345)
        XCTAssertEqual(tx.memo, "")
    }

    @MainActor
    func testRippleNumericMemoResolvesAsTag() throws {
        // The long-standing "type the tag into the memo" workaround keeps
        // working and now surfaces as a first-class tag.
        let vm = Self.makeRippleForm()
        vm.memo = "777"

        XCTAssertTrue(vm.validateRippleTagAndMemo())
        let tx = try vm.makeTransaction()
        XCTAssertEqual(tx.destinationTag, 777)
        XCTAssertEqual(tx.memo, "", "the resolved tag owns the memo slot")
    }

    @MainActor
    func testRippleTagAndMatchingMemoPass() {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "42"
        vm.memo = "42"
        XCTAssertTrue(vm.validateRippleTagAndMemo())
    }

    @MainActor
    func testRippleTagAndConflictingMemoBlocked() {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "42"
        vm.memo = "43"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagMemoConflictError")
    }

    @MainActor
    func testRippleTextMemoBlockedWithSteeringCopy() {
        let vm = Self.makeRippleForm()
        vm.memo = "thanks for lunch"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "xrpMemoNotDestinationTagError")
    }

    @MainActor
    func testRippleLeadingZeroTagBlocked() {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "0123"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    @MainActor
    func testRippleTagAboveU32MaxBlocked() {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "4294967296"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    @MainActor
    func testRippleZeroTagBlocked() {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "0"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    @MainActor
    func testRippleZeroMemoBlocked() {
        let vm = Self.makeRippleForm()
        vm.memo = "0"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    @MainActor
    func testNonRippleChainSkipsTagRule() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.memo = "any text memo is fine elsewhere"
        XCTAssertTrue(vm.validateRippleTagAndMemo())
    }

    @MainActor
    func testResetClearsDestinationTag() {
        let vm = Self.makeRippleForm()
        vm.destinationTag = "12345"
        vm.reset(to: SendFormFixture.makeBTC())
        XCTAssertEqual(vm.destinationTag, "")
    }

    // MARK: - Fixtures

    private static let destination = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"

    @MainActor
    private static func makeRippleForm() -> SendDetailsViewModel {
        let xrp = SendFormFixture.makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true, rawBalance: "100000000")
        let vm = SendFormFixture.make(coin: xrp)
        vm.toAddress = destination
        vm.amount = "1.0"
        return vm
    }

    @MainActor
    private static func makeSendTransaction(memo: String, destinationTag: UInt32?) -> SendTransaction {
        let xrp = SendFormFixture.makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true, rawBalance: "100000000")
        let vault = SendFormFixture.makeVault(coins: [xrp])
        return SendTransaction(
            coin: xrp,
            vault: vault,
            fromAddress: xrp.address,
            toAddress: destination,
            toAddressLabel: nil,
            amount: "1.0",
            amountInFiat: "",
            memo: memo,
            destinationTag: destinationTag,
            gas: BigInt(10),
            fee: BigInt(10),
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: xrp
        )
    }

    private static func makeRipplePayload(memo: String?, withSwapPayload: Bool = false) -> KeysignPayload {
        // Compressed secp256k1 generator point — a valid public key so the
        // signing-input builder gets past its key checks.
        let meta = CoinMeta(
            chain: .ripple,
            ticker: "XRP",
            logo: "xrp",
            decimals: 6,
            priceProviderId: "ripple",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy",
            hexPublicKey: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        )
        let swapPayload: SwapPayload? = withSwapPayload
            ? .swapkit(SwapKitSwapPayload(
                fromCoin: coin,
                toCoin: coin,
                fromAmount: BigInt(1_000_000),
                toAmountDecimal: 1,
                txType: "XRP",
                txPayload: Data(),
                targetAddress: destination,
                inboundAddress: nil,
                memo: memo,
                subProvider: "NEAR",
                swapID: "test-swap"
            ))
            : nil
        return KeysignPayload(
            coin: coin,
            toAddress: destination,
            toAmount: BigInt(1_000_000),
            chainSpecific: .Ripple(sequence: 99, gas: 10, lastLedgerSequence: 12345678),
            utxos: [],
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "iPhone-test",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
