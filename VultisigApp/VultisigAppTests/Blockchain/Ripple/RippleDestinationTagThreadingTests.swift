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

    func testTextMemoRestoresMemosBlob() throws {
        // #4755: a genuine text memo on a plain send (no tag field) is restored
        // as an on-chain `Memos` blob — the pre-#4749 memo-only capability. It
        // is byte-identical old-vs-new device: no field on the wire, same text
        // in the memo slot, so every platform builds the same Memos-only tx.
        // Anything that isn't a clean canonical uint32 (text, leading zeros,
        // trailing space, > uint32-max) is treated as text.
        for memo in ["tag:12345", "hello", "12345 ", "0123", "4294967296"] {
            let payload = Self.makeRipplePayload(memo: memo)
            let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
            XCTAssertFalse(input.rawJson.isEmpty, "text memo must ride an on-chain Memos blob for \"\(memo)\"")
            XCTAssertTrue(input.rawJson.contains("Memos"))
            XCTAssertEqual(input.opPayment.destinationTag, 0, "no destination tag for a text-memo-only send")
        }
    }

    func testCanonicalMemoStillBecomesTagNotMemosBlob() throws {
        // The counterpart: a numeric-canonical memo (no field) stays the legacy
        // tag carrier, never a Memos blob. "0" is still rejected (zero tag).
        let tagged = Self.makeRipplePayload(memo: "12345")
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: tagged))
        XCTAssertEqual(input.opPayment.destinationTag, 12345)
        XCTAssertTrue(input.rawJson.isEmpty)

        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: Self.makeRipplePayload(memo: "0"))) { error in
            XCTAssertEqual(error as? RippleMemoError, .invalidMemo("0"))
        }
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

    func testFieldWithConflictingNumericMemoRejects() {
        // #4755: a field tag alongside a DIFFERENT canonical number in the memo
        // slot is a tag/memo conflict (the memo would read as a second tag).
        // Reject deterministically — only reachable via a malformed payload; the
        // form blocks it.
        let conflicting = Self.makeRipplePayload(memo: "111", destinationTagField: 222)
        XCTAssertThrowsError(try RippleHelper.getPreSignedInputData(keysignPayload: conflicting)) { error in
            XCTAssertEqual(error as? RippleMemoError, .tagMemoConflict(tag: 222, memo: "111"))
        }
    }

    func testFieldWithTextMemoBuildsCombo() throws {
        // #4755: a field tag alongside a genuine TEXT memo is the tag+memo combo
        // — a rawJson Payment carrying BOTH DestinationTag and Memos. (An old
        // memo-only peer reads only the text → builds a Memos-only tx without
        // the tag → the ceremony fails safe. Accepted mixed-version limitation.)
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(
            keysignPayload: Self.makeRipplePayload(memo: "gift for alice", destinationTagField: 4321)
        ))
        XCTAssertFalse(input.rawJson.isEmpty, "combo must ride rawJson (no native memo slot)")
        XCTAssertTrue(input.rawJson.contains("Memos"))
        XCTAssertTrue(input.rawJson.contains("DestinationTag"))
        XCTAssertEqual(input.opPayment.destinationTag, 0, "combo uses rawJson, not the typed opPayment tag")

        // Prove the tag rode into the rawJson as the exact numeric value.
        let json = try Self.decodeRawJson(input.rawJson)
        XCTAssertEqual(json["DestinationTag"] as? Int, 4321)
        XCTAssertNotNil(json["Memos"])
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

    // MARK: - #4755 tag+memo combo + echo disambiguation (byte-parity)

    func testEchoMemoBuildsTagOnlyByteIdenticalToFieldOnly() throws {
        // The dual-write ECHO: field=12345 AND memo=="12345" (the tag's own
        // canonical decimal) must build the SAME tag-only payment as the
        // field-only / memo-only paths — NO Memos blob. Extends the byte-parity
        // pin to the steady-state dual-write an initiator emits for a tag-only
        // send.
        let fieldOnly = Self.makeRipplePayload(memo: nil, destinationTagField: 12345)
        let echo = Self.makeRipplePayload(memo: "12345", destinationTagField: 12345)

        let fieldInput = try RippleHelper.getPreSignedInputData(keysignPayload: fieldOnly)
        let echoInput = try RippleHelper.getPreSignedInputData(keysignPayload: echo)
        XCTAssertEqual(echoInput, fieldInput, "the echo must serialize identically to the tag-only path")

        let decoded = try RippleSigningInput(serializedBytes: echoInput)
        XCTAssertEqual(decoded.opPayment.destinationTag, 12345)
        XCTAssertTrue(decoded.rawJson.isEmpty, "the echo must NOT produce a numeric Memos blob")

        XCTAssertEqual(
            try RippleHelper.getPreSignedImageHash(keysignPayload: echo),
            try RippleHelper.getPreSignedImageHash(keysignPayload: fieldOnly),
            "the committee hash must match across field-only and echo"
        )
    }

    func testEchoSwallowsTextMemoEqualToTagDecimal() throws {
        // Accepted edge: a field tag N with a text memo that is literally the
        // decimal "N" is indistinguishable from the echo and is swallowed as
        // tag-only (no Memos). Documented + accepted.
        let payload = Self.makeRipplePayload(memo: "5", destinationTagField: 5)
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
        XCTAssertEqual(input.opPayment.destinationTag, 5)
        XCTAssertTrue(input.rawJson.isEmpty, "memo \"5\" alongside tag 5 is swallowed as the echo — no Memos")
    }

    func testRawJsonHonorsDestinationTag() throws {
        // FUND-CRITICAL: wallet-core's RippleOperationPayment has NO memo field,
        // so the combo must go through rawJson. Prove rawJson's DestinationTag
        // is encoded into the SIGNED bytes: a rawJson Payment with a tag hashes
        // DIFFERENTLY from the same Payment without one, and two different tags
        // sign differently. If wallet-core ignored the rawJson tag these would
        // collide.
        //
        // We do NOT assert byte-equality with the native opPayment-tag path:
        // wallet-core's typed builder stamps `Flags` (tfFullyCanonicalSig) on
        // the Payment, while the rawJson path signs the JSON literally (exactly
        // as the shipped swap rawJson path does, without that flag). The tag
        // itself still serializes into the signed transaction — which is what
        // this test pins.
        let noTag = try Self.rawJsonTagOnlySigningInput(tag: nil)
        let tag5 = try Self.rawJsonTagOnlySigningInput(tag: 5)
        let tag6 = try Self.rawJsonTagOnlySigningInput(tag: 6)
        XCTAssertNotEqual(try Self.preImageHash(noTag), try Self.preImageHash(tag5),
                          "DestinationTag must enter the signed rawJson bytes")
        XCTAssertNotEqual(try Self.preImageHash(tag5), try Self.preImageHash(tag6),
                          "different destination tags must sign differently")
    }

    func testComboTagAffectsSignedBytes() throws {
        // Differential proof the combo's DestinationTag enters the signed bytes:
        // two combos identical except for the tag hash DIFFERENTLY; two identical
        // except for the memo text hash DIFFERENTLY; and the combo differs from a
        // memo-only send (the tag adds bytes). Together these prove BOTH fields
        // are signed.
        let comboTag5 = try RippleHelper.getPreSignedImageHash(keysignPayload: Self.makeRipplePayload(memo: "hi", destinationTagField: 5))
        let comboTag6 = try RippleHelper.getPreSignedImageHash(keysignPayload: Self.makeRipplePayload(memo: "hi", destinationTagField: 6))
        XCTAssertNotEqual(comboTag5, comboTag6, "the destination tag must affect the signed transaction")

        let comboMemoA = try RippleHelper.getPreSignedImageHash(keysignPayload: Self.makeRipplePayload(memo: "aaa", destinationTagField: 5))
        XCTAssertNotEqual(comboTag5, comboMemoA, "the memo text must affect the signed transaction")

        let memoOnly = try RippleHelper.getPreSignedImageHash(keysignPayload: Self.makeRipplePayload(memo: "hi", destinationTagField: nil))
        XCTAssertNotEqual(comboTag5, memoOnly, "the combo (tag+memo) must differ from a memo-only send")
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
    func testPayloadMemoEchoWhenTagOnly() {
        // Tag-only send (blank memo): the memo slot echoes the tag's canonical
        // decimal so a legacy memo-only co-signer rebuilds the identical tag.
        let tx = Self.makeSendTransaction(memo: "", destinationTag: 12345)
        XCTAssertEqual(SendCryptoVerifyLogic.payloadMemo(tx: tx), "12345")
    }

    @MainActor
    func testPayloadMemoTextRidesTheSlotForCombo() {
        // Combo: a genuine text memo alongside a tag rides the memo slot as-is
        // (the tag rides the first-class field, not the memo).
        let tx = Self.makeSendTransaction(memo: "hello", destinationTag: 12345)
        XCTAssertEqual(SendCryptoVerifyLogic.payloadMemo(tx: tx), "hello")
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
    func testRippleTextMemoRestoredAsMemoOnly() throws {
        // #4755: a plain XRP send accepts a text memo again — it threads through
        // as a memo-only send (no tag), restoring the on-chain Memos capability.
        let vm = Self.makeRippleForm()
        vm.memo = "thanks for lunch"
        XCTAssertTrue(vm.validateRippleTagAndMemo())
        let tx = try vm.makeTransaction()
        XCTAssertNil(tx.destinationTag)
        XCTAssertEqual(tx.memo, "thanks for lunch")
        XCTAssertEqual(SendCryptoVerifyLogic.payloadMemo(tx: tx), "thanks for lunch")
    }

    @MainActor
    func testRippleTagAndTextMemoThreadsAsCombo() throws {
        // #4755 combo: a tag field AND a genuine text memo both survive to the
        // transaction — the tag rides the dedicated field, the text rides the
        // memo slot.
        let vm = Self.makeRippleForm()
        vm.rippleTag.destinationTag = "12345"
        vm.memo = "gift for alice"
        XCTAssertTrue(vm.validateRippleTagAndMemo())
        let tx = try vm.makeTransaction()
        XCTAssertEqual(tx.destinationTag, 12345)
        XCTAssertEqual(tx.memo, "gift for alice")
        XCTAssertEqual(SendCryptoVerifyLogic.payloadMemo(tx: tx), "gift for alice")

        // End to end: the combo builds a rawJson Payment carrying BOTH fields.
        let chainSpecific = SendCryptoVerifyLogic.dualWritingRippleTag(
            .Ripple(sequence: 1, gas: 10, lastLedgerSequence: 100), tag: tx.destinationTag
        )
        guard case .Ripple(_, _, _, let fieldTag) = chainSpecific else { return XCTFail("expected Ripple") }
        let payload = Self.makeRipplePayload(memo: SendCryptoVerifyLogic.payloadMemo(tx: tx), destinationTagField: fieldTag)
        let input = try RippleSigningInput(serializedBytes: RippleHelper.getPreSignedInputData(keysignPayload: payload))
        XCTAssertTrue(input.rawJson.contains("DestinationTag"))
        XCTAssertTrue(input.rawJson.contains("Memos"))
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
    private static let account = "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
    private static let publicKeyHex = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"

    private static func decodeRawJson(_ rawJson: String) throws -> [String: Any] {
        let data = try XCTUnwrap(rawJson.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func preImageHash(_ inputData: Data) throws -> Data {
        let hashes = TransactionCompiler.preImageHashes(coinType: .xrp, txInputData: inputData)
        let output = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(output.errorMessage.isEmpty, "wallet-core rejected the input: \(output.errorMessage)")
        return output.dataHash
    }

    /// A rawJson Payment optionally carrying a numeric DestinationTag (no
    /// Memos) — used to prove wallet-core's rawJson path encodes the tag into
    /// the signed bytes.
    private static func rawJsonTagOnlySigningInput(tag: UInt32?) throws -> Data {
        let keyData = try XCTUnwrap(Data(hexString: publicKeyHex))
        let publicKey = try XCTUnwrap(PublicKey(data: keyData, type: .secp256k1))
        var txJson: [String: Any] = [
            "TransactionType": "Payment",
            "Account": account,
            "Destination": destination,
            "Amount": "1000000",
            "Fee": "10",
            "Sequence": 99,
            "LastLedgerSequence": 12345678
        ]
        if let tag {
            txJson["DestinationTag"] = tag
        }
        let jsonString = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: txJson), encoding: .utf8))
        let input = RippleSigningInput.with {
            $0.fee = 10
            $0.sequence = 99
            $0.account = account
            $0.publicKey = publicKey.data
            $0.lastLedgerSequence = 12345678
            $0.rawJson = jsonString
        }
        return try input.serializedData()
    }

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
