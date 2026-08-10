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

    /// Base64 BCS `TransactionData` and a submit-format signature envelope.
    /// Deliberately chosen to contain `+`, `/` and `=` — the characters a naive
    /// re-encoding (URL-safe base64, percent-encoding, JSON escaping) would
    /// mangle.
    private static let txBytes = "AAACAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKzEcQySgAAAAAAQ=="
    private static let signature = "AGRlYWRiZWVmL2RlYWRiZWVmK2RlYWRiZWVmZGVhZGJlZWZkZWFkYmVlZg=="

    // MARK: - Broadcast

    func testBroadcastBodySerializesTheSignedBytesUnchanged() throws {
        let target = SuiGraphQLAPI(
            document: SuiGraphQLDocument.executeTransaction,
            variables: ["txBytes": Self.txBytes, "signatures": [Self.signature]]
        )

        let body = try Self.serializedBody(of: target)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))

        // The literal strings must survive JSON serialization character for
        // character — no escaping of `+` or `/`, no stripped `=` padding.
        XCTAssertTrue(text.contains(Self.txBytes), "transaction bytes were altered in the request body")
        XCTAssertTrue(text.contains(Self.signature), "signature envelope was altered in the request body")

        // And they must round-trip back out of the wire format identically.
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try XCTUnwrap(parsed["variables"] as? [String: Any])
        XCTAssertEqual(variables["txBytes"] as? String, Self.txBytes)
        XCTAssertEqual(variables["signatures"] as? [String], [Self.signature])
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

    func testCoinTypeUnwrapRejectsANonGenericType() {
        // The query filters to coin objects, so this should not occur — and if
        // it does, dropping the object beats guessing at its type.
        XCTAssertNil(SuiCoinType.unwrap("0x2::sui::SUI"))
        XCTAssertNil(SuiCoinType.unwrap("0x2::coin::Coin<>"))
        XCTAssertNil(SuiCoinType.unwrap(""))
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
