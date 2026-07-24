//
//  Multicall3Tests.swift
//  VultisigAppTests
//
//  Covers the Multicall3 address allowlist and the pure aggregate3 encode/decode
//  helpers used to batch EVM balance reads into one eth_call. The live
//  "values match pre-change" acceptance (AC#4) is verified manually against an
//  EVM-heavy vault; these unit tests pin the address table and the ABI layout.
//

@testable import VultisigApp
import BigInt
import XCTest

final class Multicall3Tests: XCTestCase {

    /// 32-byte ABI word (big-endian, left-padded) for a small non-negative int.
    private func w(_ value: Int) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    // MARK: - Address table

    func test_address_canonicalChains_returnCanonicalDeployment() {
        for chain in [Chain.ethereum, .bscChain, .avalanche, .base, .arbitrum,
                      .polygon, .optimism, .blast, .cronosChain, .mantle, .hyperliquid, .sei, .robinhood] {
            XCTAssertEqual(Multicall3.address(for: chain), Multicall3.canonical, "\(chain.name)")
        }
    }

    func test_address_zkSync_usesNonCanonicalRedeployment() {
        // zkSync Era's address derivation differs from EVM CREATE2, so Multicall3
        // is NOT at the canonical address. Hardcoding the wrong address would, with
        // allowFailure=true, silently zero every balance — guard against it.
        XCTAssertEqual(Multicall3.address(for: .zksync), "0xF9cda624FBC7e059355ce98a31693d299FACd963")
        XCTAssertNotEqual(Multicall3.address(for: .zksync), Multicall3.canonical)
    }

    func test_address_nonMulticallChains_returnNilForFallback() {
        // Tron + non-EVM chains have no Multicall3 → caller keeps the per-token path.
        for chain in [Chain.tron, .bitcoin, .thorChain, .solana, .cardano, .gaiaChain] {
            XCTAssertNil(Multicall3.address(for: chain), "\(chain.name)")
        }
    }

    // MARK: - encodeAggregate3

    func test_encodeAggregate3_singleCall_matchesAbiLayout() {
        let calls = [(
            target: "0x0000000000000000000000000000000000000001",
            callData: "0x12345678"
        )]

        let expected = "0x82ad56cb"
            + w(0x20)       // offset to the dynamic array argument
            + w(1)          // array length
            + w(0x20)       // element[0] offset (relative to the array body)
            + w(1)          // target (address, left-padded)
            + w(1)          // allowFailure = true
            + w(0x60)       // offset to inline callData bytes (3 words)
            + w(4)          // callData byte length
            + "12345678" + String(repeating: "0", count: 56) // callData, right-padded

        XCTAssertEqual(Multicall3.encodeAggregate3(calls: calls), expected)
    }

    func test_encodeAggregate3_twoBalanceOfCalls_computesElementOffsets() {
        // Two 36-byte (selector + padded address) callData tuples. Each dynamic
        // tuple is 6 words (192 bytes); element offsets are 0x40 then 0x40 + 0xC0.
        let paddedWallet = String(repeating: "0", count: 24) + String(repeating: "1", count: 40)
        let calls = [
            (target: "0x2222222222222222222222222222222222222222", callData: "0x70a08231" + paddedWallet),
            (target: "0x3333333333333333333333333333333333333333", callData: "0x70a08231" + paddedWallet)
        ]

        let hex = Multicall3.encodeAggregate3(calls: calls).stripHexPrefix()
        let afterSelector = String(hex.dropFirst(8)) // drop the 4-byte selector

        func wordAt(_ index: Int) -> String {
            let start = afterSelector.index(afterSelector.startIndex, offsetBy: index * 64)
            let end = afterSelector.index(start, offsetBy: 64)
            return String(afterSelector[start..<end])
        }

        XCTAssertTrue(Multicall3.encodeAggregate3(calls: calls).hasPrefix("0x82ad56cb"))
        XCTAssertEqual(wordAt(0), w(0x20), "argument offset")
        XCTAssertEqual(wordAt(1), w(2), "array length")
        XCTAssertEqual(wordAt(2), w(0x40), "element[0] offset")
        XCTAssertEqual(wordAt(3), w(0x100), "element[1] offset = 0x40 + one 0xC0 tuple")
    }

    // MARK: - decodeAggregate3Results

    func test_decodeAggregate3Results_failedEntryMapsToNil_siblingsDecode() {
        // Three results: success(100), failure(empty), success(200). The failed
        // entry must map to nil (caller → 0) without affecting its siblings.
        let response = "0x"
            + w(0x20)       // offset to Result[]
            + w(3)          // array length
            + w(0x60)       // element[0] offset
            + w(0xe0)       // element[1] offset
            + w(0x140)      // element[2] offset
            // result[0]: success, returnData = uint256(100)
            + w(1) + w(0x40) + w(0x20) + w(100)
            // result[1]: failure, empty returnData
            + w(0) + w(0x40) + w(0)
            // result[2]: success, returnData = uint256(200)
            + w(1) + w(0x40) + w(0x20) + w(200)

        let decoded = Multicall3.decodeAggregate3Results(hex: response)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0], BigInt(100))
        XCTAssertNil(decoded[1])
        XCTAssertEqual(decoded[2], BigInt(200))
    }

    func test_decodeAggregate3Results_malformedHex_returnsEmpty() {
        XCTAssertTrue(Multicall3.decodeAggregate3Results(hex: "0x").isEmpty)
        XCTAssertTrue(Multicall3.decodeAggregate3Results(hex: "not-hex").isEmpty)
    }

    // MARK: - mapBalances
    //
    // `aggregate3` returns success at the top level even when a sub-call fails, so
    // this mapping is the only place a partial failure can be told apart from a
    // genuine zero. Collapsing the two here persists an empty balance over a
    // funded coin, with no throw and no fallback to catch it.

    func testMapBalancesOmitsFailedSubCallRatherThanZeroingIt() {
        // USDC's sub-call failed (nil). It must be ABSENT — not present-as-zero —
        // so the caller retries it instead of writing 0 over a funded coin.
        let mapped = Multicall3.mapBalances(
            decoded: [BigInt(500), nil, BigInt(200)],
            includeNative: false,
            contractAddresses: ["0xDAI", "0xUSDC", "0xWBTC"]
        )

        XCTAssertNil(mapped?.balances["0xUSDC"], "a failed sub-call must not be recorded at all")
        XCTAssertFalse(mapped?.balances.keys.contains("0xUSDC") ?? true, "absent, not zero")
        XCTAssertEqual(mapped?.balances["0xDAI"], BigInt(500), "siblings still resolve")
        XCTAssertEqual(mapped?.balances["0xWBTC"], BigInt(200), "siblings still resolve")
    }

    func testMapBalancesKeepsGenuineZeroBalance() {
        // An empty wallet is a real balance and must survive as 0 — the fix must
        // not "preserve" its way into never writing zeroes.
        let mapped = Multicall3.mapBalances(
            decoded: [BigInt(0), nil],
            includeNative: false,
            contractAddresses: ["0xEMPTY", "0xFAILED"]
        )

        XCTAssertEqual(mapped?.balances["0xEMPTY"], BigInt(0), "a genuine zero is a real balance")
        XCTAssertTrue(mapped?.balances.keys.contains("0xEMPTY") ?? false)
        XCTAssertFalse(mapped?.balances.keys.contains("0xFAILED") ?? true)
    }

    func testMapBalancesFailedNativeCallIsNilWhileTokensResolve() {
        let mapped = Multicall3.mapBalances(
            decoded: [nil, BigInt(42)],
            includeNative: true,
            contractAddresses: ["0xDAI"]
        )

        XCTAssertNil(mapped?.native, "a failed native read must not become a 0 balance")
        XCTAssertEqual(mapped?.balances["0xDAI"], BigInt(42))
    }

    func testMapBalancesNativeZeroIsDistinctFromNativeFailure() {
        let zero = Multicall3.mapBalances(decoded: [BigInt(0)], includeNative: true, contractAddresses: [])
        let failed = Multicall3.mapBalances(decoded: [nil], includeNative: true, contractAddresses: [])

        XCTAssertEqual(zero?.native, BigInt(0))
        XCTAssertNil(failed?.native)
    }

    func testMapBalancesAssignsResultsInCallOrderWithNativeFirst() {
        // Order is the contract: native getEthBalance first, then one balanceOf per
        // contract in the order given. A drift here silently swaps balances between
        // tokens.
        let mapped = Multicall3.mapBalances(
            decoded: [BigInt(1), BigInt(2), BigInt(3)],
            includeNative: true,
            contractAddresses: ["0xA", "0xB"]
        )

        XCTAssertEqual(mapped?.native, BigInt(1))
        XCTAssertEqual(mapped?.balances["0xA"], BigInt(2))
        XCTAssertEqual(mapped?.balances["0xB"], BigInt(3))
    }

    func testMapBalancesCountMismatchReturnsNilSoCallerFallsBack() {
        // A short decode must read as a whole-batch failure, never as a partial
        // success that zeroes the missing tail.
        XCTAssertNil(Multicall3.mapBalances(decoded: [], includeNative: false, contractAddresses: ["0xA"]))
        XCTAssertNil(Multicall3.mapBalances(decoded: [BigInt(1)], includeNative: true, contractAddresses: ["0xA"]))
        XCTAssertNil(Multicall3.mapBalances(decoded: [BigInt(1), BigInt(2)], includeNative: false, contractAddresses: ["0xA"]))
    }

    func testMapBalancesDecodedFailureRoundTripsFromRealAggregate3Response() {
        // End-to-end over the pure pair: the mixed success/failure/success fixture
        // decoded above must land as "middle token absent", not "middle token 0".
        let response = "0x"
            + w(0x20) + w(3)
            + w(0x60) + w(0xe0) + w(0x140)
            + w(1) + w(0x40) + w(0x20) + w(100)   // success 100
            + w(0) + w(0x40) + w(0)               // failure
            + w(1) + w(0x40) + w(0x20) + w(200)   // success 200

        let decoded = Multicall3.decodeAggregate3Results(hex: response)
        let mapped = Multicall3.mapBalances(
            decoded: decoded,
            includeNative: false,
            contractAddresses: ["0xA", "0xB", "0xC"]
        )

        XCTAssertEqual(mapped?.balances["0xA"], BigInt(100))
        XCTAssertFalse(mapped?.balances.keys.contains("0xB") ?? true, "the failed sub-call must not surface as 0")
        XCTAssertEqual(mapped?.balances["0xC"], BigInt(200))
    }
}
