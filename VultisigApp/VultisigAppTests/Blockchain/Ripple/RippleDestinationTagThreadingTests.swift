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

    // MARK: - Cosigner display resolution (field-preferred)

    func testDisplayTagPrefersField() {
        let payload = Self.makeRipplePayload(memo: "111", destinationTagField: 222)
        XCTAssertEqual(RippleDestinationTag.displayTag(for: payload), 222)
    }

    func testDisplayTagFallsBackToCanonicalMemo() {
        let payload = Self.makeRipplePayload(memo: "12345", destinationTagField: nil)
        XCTAssertEqual(RippleDestinationTag.displayTag(for: payload), 12345)
    }

    func testDisplayTagNilForTaglessPayload() {
        XCTAssertNil(RippleDestinationTag.displayTag(for: Self.makeRipplePayload(memo: nil, destinationTagField: nil)))
    }

    func testDisplayTagNilForNonCanonicalMemoWithoutField() {
        // A text swap memo (no field) has no destination tag to display.
        XCTAssertNil(RippleDestinationTag.displayTag(for: Self.makeRipplePayload(memo: "=:ETH.ETH:0x1", destinationTagField: nil)))
    }

    func testDisplayTagIgnoresZeroField() {
        // A malformed present-0 field is not a displayable tag (and won't sign).
        XCTAssertNil(RippleDestinationTag.displayTag(for: Self.makeRipplePayload(memo: nil, destinationTagField: 0)))
    }

    func testDisplayTagNilForSwapPayloads() {
        // Swaps are out of scope for the Destination Tag row — the signer
        // resolves swap tags from the memo with different (lenient) rules, and
        // swaps keep their existing memo-row display. Neither a field nor a
        // numeric memo promotes a swap to a tag row, so a displayed tag can
        // never diverge from the signed one and a routing memo is never hidden.
        XCTAssertNil(RippleDestinationTag.displayTag(for: Self.makeRipplePayload(memo: "=:ETH.ETH:0x1234:0/1/0", destinationTagField: 999, withSwapPayload: true)))
        XCTAssertNil(RippleDestinationTag.displayTag(for: Self.makeRipplePayload(memo: "54321", destinationTagField: nil, withSwapPayload: true)))
    }

    func testDisplayTagZeroFieldDoesNotFallThroughToMemo() {
        // A present field is terminal (mirrors the signer): a malformed 0 field
        // is not displayable and must NOT fall back to a memo tag.
        let payload = Self.makeRipplePayload(memo: "123", destinationTagField: 0)
        XCTAssertNil(RippleDestinationTag.displayTag(for: payload))
    }

    // MARK: - Proto round-trip (the wire the co-signer receives)

    func testDestinationTagSurvivesProtoRoundTrip() throws {
        // The co-signer never rebuilds the payload — it deserializes the proto
        // the initiator serialized. Pin that a set field round-trips through
        // the RippleSpecific proto so the field-preferring signer can read it.
        let original: BlockChainSpecific = .Ripple(sequence: 5, gas: 10, lastLedgerSequence: 99, destinationTag: 4242)

        guard case .rippleSpecific(let ripple) = original.mapToProtobuff() else {
            return XCTFail("expected rippleSpecific oneof")
        }
        XCTAssertTrue(ripple.hasDestinationTag)
        XCTAssertEqual(ripple.destinationTag, 4242)

        guard case .Ripple(_, _, _, let tag) = try BlockChainSpecific(proto: original.mapToProtobuff()) else {
            return XCTFail("expected Ripple case")
        }
        XCTAssertEqual(tag, 4242)
    }

    func testAbsentDestinationTagStaysUnsetOnTheWire() throws {
        // Byte-parity guarantee for memo-only sends: with no field the proto
        // leaves destination_tag UNSET, so an old memo-only co-signer sees the
        // exact same RippleSpecific bytes it always did (the field is not even
        // present to ignore).
        let original: BlockChainSpecific = .Ripple(sequence: 5, gas: 10, lastLedgerSequence: 99, destinationTag: nil)

        guard case .rippleSpecific(let ripple) = original.mapToProtobuff() else {
            return XCTFail("expected rippleSpecific oneof")
        }
        XCTAssertFalse(ripple.hasDestinationTag, "no field → unset on the wire")

        guard case .Ripple(_, _, _, let tag) = try BlockChainSpecific(proto: original.mapToProtobuff()) else {
            return XCTFail("expected Ripple case")
        }
        XCTAssertNil(tag)
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

    // MARK: - First-class field ⇄ memo byte parity (dual-write safety)

    func testFieldSourcedTagProducesByteIdenticalInputToMemoFallback() throws {
        // THE dual-write safety pin. A tag delivered via the first-class
        // `RippleSpecific.destination_tag` field must produce a byte-identical
        // pre-signed input (and pre-image hash) to the SAME tag delivered via
        // the legacy memo carrier — proving a new-version signer (reads the
        // field) and an old-version co-signer (reads only the memo) hash the
        // exact same transaction in an MPC ceremony.
        let viaField = Self.makeRipplePayload(memo: nil, destinationTagField: 12345)
        let viaMemo = Self.makeRipplePayload(memo: "12345", destinationTagField: nil)

        let fieldInput = try RippleHelper.getPreSignedInputData(keysignPayload: viaField)
        let memoInput = try RippleHelper.getPreSignedInputData(keysignPayload: viaMemo)
        XCTAssertEqual(fieldInput, memoInput, "field-sourced and memo-sourced tags must serialize identically")

        let decoded = try RippleSigningInput(serializedBytes: fieldInput)
        XCTAssertEqual(decoded.opPayment.destinationTag, 12345)
        XCTAssertTrue(decoded.rawJson.isEmpty, "tagged payments never take the rawJson path")

        let fieldHash = try RippleHelper.getPreSignedImageHash(keysignPayload: viaField)
        let memoHash = try RippleHelper.getPreSignedImageHash(keysignPayload: viaMemo)
        XCTAssertFalse(fieldHash.isEmpty)
        XCTAssertEqual(fieldHash, memoHash, "the pre-image hash the committee signs must match")
    }

    func testFieldPreferredWhenBothCarriersAgree() throws {
        // Dual-write steady state: both carriers set to the SAME value. The
        // signer prefers the field; the built tag matches the memo-only build.
        let both = Self.makeRipplePayload(memo: "777", destinationTagField: 777)
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: both))
        XCTAssertEqual(input.opPayment.destinationTag, 777)
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    func testFieldWinsOverConflictingMemo() throws {
        // Deterministic conflict rule: when the field and memo disagree, the
        // field wins outright (only reachable via a malformed payload — the
        // initiator always dual-writes equal values). The signed tag is the
        // field's value; the divergent memo is ignored.
        let conflicting = Self.makeRipplePayload(memo: "111", destinationTagField: 222)
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: conflicting))
        XCTAssertEqual(input.opPayment.destinationTag, 222, "the first-class field wins over a conflicting memo")
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    func testFieldWinsEvenWhenMemoIsNonCanonical() throws {
        // Prefer-field short-circuits memo validation: a present field signs
        // successfully even if the memo carrier is non-canonical. (An old
        // memo-only peer would reject that memo and fail the ceremony — safe,
        // never a bad signature.)
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(
            keysignPayload: Self.makeRipplePayload(memo: "not-a-tag", destinationTagField: 4321)
        ))
        XCTAssertEqual(input.opPayment.destinationTag, 4321)
        XCTAssertTrue(input.rawJson.isEmpty)
    }

    func testFieldPresentZeroRejectsPayload() {
        // A present field of 0 must reject exactly as memo "0" does: wallet-core
        // encodes a 0 destinationTag identically to "no tag", so signing it
        // would send UNTAGGED while a tag was displayed (dishonest signing).
        let payload = Self.makeRipplePayload(memo: nil, destinationTagField: 0)
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertEqual(error as? RippleMemoError, .invalidMemo("0"))
        }
    }

    func testMemoFallbackWhenFieldAbsent() throws {
        // No field → the memo carrier is the source of truth (unchanged from
        // the pre-field behavior, and what every legacy platform does).
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(
            keysignPayload: Self.makeRipplePayload(memo: "888", destinationTagField: nil)
        ))
        XCTAssertEqual(input.opPayment.destinationTag, 888)
        XCTAssertTrue(input.rawJson.isEmpty)
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

    // MARK: - Dual-write (initiator sets BOTH carriers)

    func testDualWriteSetsFieldFromResolvedTag() throws {
        let base: BlockChainSpecific = .Ripple(sequence: 1, gas: 10, lastLedgerSequence: 100)
        let written = SendCryptoVerifyLogic.dualWritingRippleTag(base, tag: try RippleDestinationTag.validatePayloadMemo("12345"))
        guard case .Ripple(_, _, _, let fieldTag) = written else { return XCTFail("expected Ripple") }
        XCTAssertEqual(fieldTag, 12345)
    }

    @MainActor
    func testDualWriteFieldEqualsMemoCarrier() throws {
        // The dual-write invariant: the first-class field and the memo carrier
        // hold the SAME value (both derived from the one resolved tag).
        let tx = Self.makeSendTransaction(memo: "", destinationTag: 4242)
        let memo = SendCryptoVerifyLogic.payloadMemo(tx: tx)
        XCTAssertEqual(memo, "4242")

        let base: BlockChainSpecific = .Ripple(sequence: 1, gas: 10, lastLedgerSequence: 100)
        let written = SendCryptoVerifyLogic.dualWritingRippleTag(base, tag: try RippleDestinationTag.validatePayloadMemo(memo))
        guard case .Ripple(_, _, _, let fieldTag) = written else { return XCTFail("expected Ripple") }
        XCTAssertEqual(fieldTag.map(String.init), memo, "field and memo carriers must hold the same value")
    }

    func testDualWriteLeavesFieldUnsetForTaglessSend() {
        let base: BlockChainSpecific = .Ripple(sequence: 1, gas: 10, lastLedgerSequence: 100)
        let written = SendCryptoVerifyLogic.dualWritingRippleTag(base, tag: nil)
        guard case .Ripple(_, _, _, let fieldTag) = written else { return XCTFail("expected Ripple") }
        XCTAssertNil(fieldTag, "no tag → field unset → byte-identical for memo-only co-signers")
    }

    func testDualWriteNoOpForNonRipple() {
        let base: BlockChainSpecific = .Ton(sequenceNumber: 1, expireAt: 2, bounceable: true, sendMaxAmount: false)
        let written = SendCryptoVerifyLogic.dualWritingRippleTag(base, tag: 999)
        guard case .Ton = written else { return XCTFail("non-Ripple must pass through unchanged") }
    }

    // MARK: - Form seam (SendDetailsViewModel)

    @MainActor
    func testRippleTagFieldThreadsIntoTransaction() throws {
        let vm = Self.makeRippleForm()
        vm.rippleTag.destinationTag = "12345"

        XCTAssertTrue(vm.validateRippleTagAndMemo())
        let tx = try vm.makeTransaction()
        XCTAssertEqual(tx.destinationTag, 12345)
        XCTAssertEqual(tx.memo, "")
    }

    @MainActor
    func testManualTagThreadsEndToEndToSignedDestinationTag() throws {
        // Verified mainnet case: a manually-typed tag 1234 on a plain classic
        // address reaches the signed WalletCore Payment as DestinationTag=1234
        // (memo blanked). Pins the whole seam — VM tag field → SendTransaction
        // → payload memo → RippleHelper signing input — with the exact value.
        let vm = Self.makeRippleForm()
        vm.rippleTag.destinationTag = "1234"

        XCTAssertTrue(vm.validateRippleTagAndMemo())
        let tx = try vm.makeTransaction()
        XCTAssertEqual(tx.destinationTag, 1234)
        XCTAssertEqual(tx.memo, "")

        let payloadMemo = SendCryptoVerifyLogic.payloadMemo(tx: tx)
        XCTAssertEqual(payloadMemo, "1234")

        let payload = Self.makeRipplePayload(memo: payloadMemo)
        let inputData = try RippleHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try RippleSigningInput(serializedBytes: inputData)
        XCTAssertEqual(input.opPayment.destinationTag, 1234)
        XCTAssertTrue(input.rawJson.isEmpty, "tagged payments never take the rawJson path")
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
        vm.rippleTag.destinationTag = "42"
        vm.memo = "42"
        XCTAssertTrue(vm.validateRippleTagAndMemo())
    }

    @MainActor
    func testRippleTagAndConflictingMemoBlocked() {
        let vm = Self.makeRippleForm()
        vm.rippleTag.destinationTag = "42"
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
        vm.rippleTag.destinationTag = "0123"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    @MainActor
    func testRippleTagAboveU32MaxBlocked() {
        let vm = Self.makeRippleForm()
        vm.rippleTag.destinationTag = "4294967296"
        XCTAssertFalse(vm.validateRippleTagAndMemo())
        XCTAssertEqual(vm.errorMessage, "destinationTagInvalidError")
    }

    @MainActor
    func testRippleZeroTagBlocked() {
        let vm = Self.makeRippleForm()
        vm.rippleTag.destinationTag = "0"
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
        vm.rippleTag.destinationTag = "12345"
        vm.reset(to: SendFormFixture.makeBTC())
        XCTAssertEqual(vm.rippleTag.destinationTag, "")
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

    private static func makeRipplePayload(memo: String?, destinationTagField: UInt32? = nil, withSwapPayload: Bool = false) -> KeysignPayload {
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
            chainSpecific: .Ripple(sequence: 99, gas: 10, lastLedgerSequence: 12345678, destinationTag: destinationTagField),
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
