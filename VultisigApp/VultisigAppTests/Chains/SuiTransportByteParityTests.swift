//
//  SuiTransportByteParityTests.swift
//  VultisigAppTests
//
//  Byte-parity goldens for the Sui transport swap.
//
//  The signing path is untouched by the move to GraphQL: `SuiHelper` and
//  `SwapKitSuiSigner` still produce the base64 `TransactionData` and the
//  `[flag ‖ sig ‖ pubkey]` envelope exactly as before (their own goldens live in
//  `SuiHelperInputDataTests`, `SuiSignSuiTests` and `SwapKitSigningTests`). What
//  changed is what the transport does with those two strings afterwards.
//
//  So these pin the boundary rather than the signature: the exact bytes that
//  leave the app. A transport regression that re-encoded, truncated, escaped or
//  reordered signed material would show up here, in the serialized request body,
//  rather than on chain.
//

@testable import VultisigApp
import XCTest

final class SuiTransportByteParityTests: XCTestCase {

    /// Valid base64 whose *text* contains literal `+`, `/` and `=`. Those three
    /// characters are the ones a naive re-encoding mangles — URL-safe base64
    /// rewrites `+`/`/` to `-`/`_`, percent-encoding escapes them, and some
    /// encoders strip `=` padding — so the fixtures have to carry them
    /// literally, not merely decode to bytes that would produce them.
    private static let txBytes = "AP/v+/8AAAACAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAKzEcQySgAAAAAAQ=="
    private static let signature = "AGRlYWRiZWVm+2RlYWRiZWVm/2RlYWRiZWVmZGVhZGJlZWZkZWFkYmVlZg=="

    /// Guards the fixtures themselves: a future edit that removed the special
    /// characters would make every assertion below pass without testing
    /// anything.
    func testFixturesActuallyContainTheCharactersUnderTest() {
        for fixture in [Self.txBytes, Self.signature] {
            XCTAssertTrue(fixture.contains("+"), "fixture lost its literal '+': \(fixture)")
            XCTAssertTrue(fixture.contains("/"), "fixture lost its literal '/': \(fixture)")
            XCTAssertTrue(fixture.hasSuffix("="), "fixture lost its padding: \(fixture)")
            XCTAssertNotNil(Data(base64Encoded: fixture), "fixture is not valid base64: \(fixture)")
        }
    }

    // MARK: - Broadcast

    func testBroadcastBodySerializesTheSignedBytesUnchanged() throws {
        let target = SuiGraphQLAPI(
            document: SuiGraphQLDocument.executeTransaction,
            variables: ["txBytes": Self.txBytes, "signatures": [Self.signature]]
        )

        let body = try Self.serializedBody(of: target)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))

        // What the node receives, after parsing, must be identical. This is the
        // assertion that matters: it is the value Sui verifies the signature
        // against.
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try XCTUnwrap(parsed["variables"] as? [String: Any])
        XCTAssertEqual(variables["txBytes"] as? String, Self.txBytes)
        XCTAssertEqual(variables["signatures"] as? [String], [Self.signature])

        // On the wire, `Foundation` escapes every `/` as `\/`. That is a valid
        // JSON string escape and any conformant parser reverses it — verified
        // against mainnet, where a real PTB whose base64 contains both `+` and
        // `/` simulates to SUCCESS when sent in exactly this encoding. `+` and
        // the `=` padding are NOT escaped, and must not be: a `+` rewritten to
        // `-`, or padding stripped, would be URL-safe base64 and a different
        // value.
        XCTAssertTrue(text.contains(Self.txBytes.replacingOccurrences(of: "/", with: "\\/")))
        XCTAssertTrue(text.contains(Self.signature.replacingOccurrences(of: "/", with: "\\/")))
        XCTAssertTrue(text.contains("+"), "'+' must be sent literally, not URL-safe-encoded")
        XCTAssertTrue(text.contains("=="), "base64 padding must not be stripped")
        XCTAssertFalse(text.contains("%2B"), "the body must not be percent-encoded")
    }

    // MARK: - Dry run

    func testSimulateBodyNestsTheSameBytesUnderTheBCSKey() throws {
        // `simulateTransaction` takes a JSON-encoded `sui.rpc.v2.Transaction`
        // rather than a bare base64 argument. The extra nesting is the ONLY
        // difference: the bytes inside must be identical to the broadcast ones,
        // or the fee was estimated for a different transaction than the one
        // being signed.
        let target = SuiGraphQLAPI(
            document: SuiGraphQLDocument.simulateTransaction,
            variables: ["tx": SuiGraphQLDocument.bcsTransaction(Self.txBytes)]
        )

        let body = try Self.serializedBody(of: target)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try XCTUnwrap(parsed["variables"] as? [String: Any])
        let transaction = try XCTUnwrap(variables["tx"] as? [String: Any])
        let bcs = try XCTUnwrap(transaction["bcs"] as? [String: Any])

        XCTAssertEqual(bcs["value"] as? String, Self.txBytes)
        XCTAssertEqual(
            Set(transaction.keys),
            ["bcs"],
            "Only the BCS arm may be sent — a partially-specified transaction would let the node fill in fields the signer never saw"
        )
    }

    func testSimulationDoesNotDelegateGasSelectionToTheNode() {
        // The caller has already built a complete gas payment from the coin
        // objects it selected. Letting the node re-pick gas would price a
        // different transaction than the one that gets signed.
        XCTAssertTrue(SuiGraphQLDocument.simulateTransaction.contains("doGasSelection: false"))
        XCTAssertTrue(SuiGraphQLDocument.simulateTransaction.contains("checksEnabled: true"))
    }

    // MARK: - Coin-type unwrapping

    func testCoinTypeUnwrapMatchesTheJSONRPCSpellingForRealMainnetTypes() {
        // Captured from mainnet: the object connection reports the wrapper
        // struct, zero-padded, where `suix_getAllCoins` reported the bare type
        // with the address stripped. `SuiTokenFinder` persists this string as a
        // discovered token's `contractAddress`, so a mismatch means the same
        // token is rediscovered as a second vault entry after the migration.
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        let cases: [(repr: String, expected: String)] = [
            ("\(padded)::coin::Coin<\(padded)::sui::SUI>", "0x2::sui::SUI"),
            (
                "\(padded)::coin::Coin<0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN>",
                "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"
            ),
            (
                "\(padded)::coin::Coin<0x0000a2b3c4d5e6f7809000000000000000000000000000000000000000000001::gold::GOLD>",
                "0xa2b3c4d5e6f7809000000000000000000000000000000000000000000001::gold::GOLD"
            )
        ]

        for testCase in cases {
            XCTAssertEqual(SuiCoinType.unwrap(testCase.repr), testCase.expected, testCase.repr)
        }
    }

    func testCoinTypeUnwrapPreservesMoveIdentifierCase() {
        // `::coin::USDC` and `::coin::usdc` are genuinely distinct Move types;
        // only the address segment may be normalized.
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        XCTAssertEqual(
            SuiCoinType.unwrap("\(padded)::coin::Coin<0xAbC::coin::USDC>"),
            "0xabc::coin::USDC"
        )
    }

    func testCoinTypeUnwrapNormalizesNestedGenericAddresses() {
        // A coin's type argument can itself be generic — LP coins are real. If
        // only the outer address is normalized, the same coin is persisted under
        // two different `contractAddress` spellings depending on which endpoint
        // reported it, and is rediscovered as a duplicate vault entry.
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        let repr = "\(padded)::coin::Coin<0x00abc::pool::LP<\(padded)::sui::SUI, 0x000def::usdc::USDC>>"

        XCTAssertEqual(
            SuiCoinType.unwrap(repr),
            "0xabc::pool::LP<0x2::sui::SUI, 0xdef::usdc::USDC>"
        )
    }

    func testCoinTypeUnwrapRejectsAnythingItCannotFullyAccountFor() {
        // The result is persisted and later compared against catalog entries, so
        // a half-parse is worse than a rejection: the object is dropped, which is
        // loud, instead of stored under a type nothing will ever match.
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        let rejected = [
            "0x2::sui::SUI",                                  // not generic at all
            "0x2::coin::Coin<>",                              // empty argument
            "",                                               // empty input
            "\(padded)::coin::Coin<0x2::sui::SUI>trailing",   // trailing text
            "\(padded)::coin::Coin<0x2::sui::SUI",            // unclosed
            "\(padded)::coin::Coin<0x2::sui::SUI>>",          // unbalanced extra '>'
            "\(padded)::coin::Coin<A>B<C>",                   // two arguments spliced
            "0x2::balance::Balance<0x2::sui::SUI>",           // a different wrapper
            "0x3::coin::Coin<0x2::sui::SUI>",                 // wrong package
            "0x2::coin::Treasury<0x2::sui::SUI>"              // wrong struct
        ]

        for repr in rejected {
            XCTAssertNil(SuiCoinType.unwrap(repr), "should have been rejected: \(repr)")
        }
    }

    func testNormalizePreservesMovePrimitivesAndVectors() {
        // `vector`, `u8`, `u64` and `bool` are delimiter-free like an address,
        // but they are not addresses. Normalizing them invents types that do not
        // exist — and this value is persisted as a token's `contractAddress`, so
        // a mangled one never matches the real coin again.
        let cases: [(input: String, expected: String)] = [
            ("0x0abc::pool::LP<u64, bool>", "0xabc::pool::LP<u64, bool>"),
            ("0x0abc::pool::LP<vector<u8>>", "0xabc::pool::LP<vector<u8>>"),
            ("0x0002::coin::Coin<0x0002::sui::SUI>", "0x2::coin::Coin<0x2::sui::SUI>"),
            ("vector<u8>", "vector<u8>"),
            ("u64", "u64")
        ]

        for testCase in cases {
            XCTAssertEqual(SuiCoinType.normalize(testCase.input), testCase.expected, testCase.input)
        }
    }

    func testCoinTypeUnwrapKeepsPrimitiveTypeArgumentsIntact() {
        let padded = "0x" + String(repeating: "0", count: 63) + "2"

        XCTAssertEqual(
            SuiCoinType.unwrap("\(padded)::coin::Coin<0x00abc::pool::LP<vector<u8>, u64>>"),
            "0xabc::pool::LP<vector<u8>, u64>"
        )
    }

    // MARK: - Telling "not a coin" from "unreadable"

    func testGenuinelyDifferentStructsAreSafeToSkip() {
        // Verified against mainnet: the `type: "0x2::coin::Coin"` filter matches
        // the exact struct, so an address holding 37 `TreasuryCap`s returns none
        // of them. These are the objects that WOULD arrive if that ever changed
        // — genuinely not coins, and losing nothing by being skipped.
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        for repr in [
            "\(padded)::coin::TreasuryCap<0x2::sui::SUI>",
            "\(padded)::coin::CoinMetadata<0x2::sui::SUI>",
            "0x2::balance::Balance<0x2::sui::SUI>",
            "0x2::sui::SUI"
        ] {
            XCTAssertNil(SuiCoinType.unwrap(repr), "not a coin: \(repr)")
            XCTAssertEqual(SuiCoinType.classifyNonCoin(repr), .differentStruct, repr)
        }
    }

    func testABrokenCoinWrapperIsNeverMistakenForADifferentStruct() {
        // The dangerous case. Each of these IS shaped like the coin wrapper but
        // fails to unwrap, so treating it as "some other object" would drop a
        // real coin out of a set that funds a transaction — silently, and with
        // the page count still looking right.
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        for repr in [
            "0x2::coin::Coin",
            "0x2::coin::Coin<>",
            "0x2::coin::Coin<0x2::sui::SUI>garbage",
            "\(padded)::coin::Coin<0x2::sui::SUI",
            "\(padded)::coin::Coin<0x2::sui::SUI>>"
        ] {
            XCTAssertNil(SuiCoinType.unwrap(repr), "must not unwrap: \(repr)")
            XCTAssertEqual(SuiCoinType.classifyNonCoin(repr), .unreadable, repr)
        }
    }

    func testUnreadableTypesAreNotMistakenForOutOfScopeObjects() {
        // We cannot say what these are, so we cannot say dropping them is safe.
        for repr in [
            "",
            "garbage",
            "0x2::coin",
            "::::",
            "0x2::::X",
            "0xZZ::coin::TreasuryCap<0x2::sui::SUI>",   // address is not hex
            "0x2::9bad::TreasuryCap<0x2::sui::SUI>",    // module is not an identifier
            "0x2::coin::Trea sury<0x2::sui::SUI>"       // struct is not an identifier
        ] {
            XCTAssertEqual(SuiCoinType.classifyNonCoin(repr), .unreadable, "should be rejected: \(repr)")
        }
    }

    func testCoinTypeUnwrapDoesNotCrashOnUnicodeOrOddInput() {
        // Bounds arithmetic on a Swift String is grapheme-based; these exist to
        // prove the parser cannot trap on input a node should never send.
        for repr in ["🙂<🙂>", "<>", "><", "0x2::coin::Coin<🙂::a::B>", String(repeating: "<", count: 64)] {
            _ = SuiCoinType.unwrap(repr)
        }
    }

    func testUnwrappedTypesStillMatchTheCanonicalNativeType() {
        let padded = "0x" + String(repeating: "0", count: 63) + "2"
        let unwrapped = try? XCTUnwrap(SuiCoinType.unwrap("\(padded)::coin::Coin<\(padded)::sui::SUI>"))
        XCTAssertTrue(SuiCoinType.isNative(unwrapped ?? ""))
        XCTAssertTrue(SuiCoinType.matches(unwrapped ?? "", SuiConstants.nativeCoinType))
    }

    // MARK: - Helpers

    /// The bytes `HTTPClient` would put on the wire for `target`.
    private static func serializedBody(of target: TargetType) throws -> Data {
        guard case .requestParameters(let parameters, .jsonEncoding) = target.task else {
            throw ByteParityError.unexpectedTask
        }
        return try JSONSerialization.data(withJSONObject: parameters, options: [])
    }

    private enum ByteParityError: Error {
        case unexpectedTask
    }
}
