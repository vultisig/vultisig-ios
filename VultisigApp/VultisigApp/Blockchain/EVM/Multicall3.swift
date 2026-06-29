//
//  Multicall3.swift
//  VultisigApp
//
//  Address table + ABI encode/decode helpers for batching EVM balance reads
//  through Multicall3 `aggregate3`. Pure value type with no I/O so the encoder
//  and decoder are unit-testable in isolation.
//

import Foundation
import BigInt

enum Multicall3 {
    /// Canonical CREATE2 deployment, identical on every supported chain except zkSync.
    static let canonical = "0xcA11bde05977b3631167028862bE2a173976CA11"

    /// zkSync Era's contract-address derivation differs from EVM CREATE2, so the
    /// canonical deterministic deployment was never reachable; Multicall3 lives at
    /// this redeployed address instead. Hardcoded — never "default to canonical".
    static let zkSyncAddress = "0xF9cda624FBC7e059355ce98a31693d299FACd963"

    /// Returns the Multicall3 contract address for `chain`, or `nil` if the chain
    /// has no verified deployment (→ caller falls back to the per-token eth_call
    /// path). This is an explicit allowlist: a future EVM chain not listed here
    /// returns `nil` and stays on the safe per-token path until verified.
    static func address(for chain: Chain) -> String? {
        switch chain {
        case .ethereum, .ethereumSepolia, .bscChain, .avalanche, .base, .arbitrum,
             .polygon, .polygonV2, .optimism, .blast, .cronosChain, .mantle,
             .hyperliquid, .sei:
            return canonical
        case .zksync:
            return zkSyncAddress
        default:
            // Tron (routed to TronService, chainID nil) + every non-EVM chain.
            return nil
        }
    }

    // 4-byte selectors (keccak256(signature)[0..4]):
    static let aggregate3Selector = "82ad56cb"   // aggregate3((address,bool,bytes)[])
    static let getEthBalanceSelector = "4d2301cc" // getEthBalance(address)
    static let balanceOfSelector = "70a08231"     // balanceOf(address)

    private static let hexWordLength = 64 // 32 bytes == 64 hex chars

    // MARK: - Encode

    /// ABI-encodes `aggregate3((address target, bool allowFailure, bytes callData)[])`
    /// calldata (selector + args, `0x`-prefixed). `allowFailure` is always `true`
    /// so a reverting sub-call yields `success = false` rather than reverting the
    /// whole batch. `callData` for each call already includes its 4-byte selector.
    static func encodeAggregate3(calls: [(target: String, callData: String)]) -> String {
        // Encode each dynamic Call3 tuple: head is target, allowFailure, and the
        // offset to the inline bytes (always 0x60 = 3 words); tail is the bytes
        // length followed by the right-padded callData.
        let encodedTuples: [String] = calls.map { call in
            let cleanData = call.callData.stripHexPrefix()
            let byteLength = cleanData.count / 2
            return paddedAddress(call.target)
                + word(1)            // allowFailure = true
                + word(0x60)         // offset to callData bytes within the tuple
                + word(byteLength)
                + rightPadded(cleanData)
        }

        // The array is a dynamic array of dynamic tuples: a section of element
        // offsets (relative to the start of the array body, i.e. right after the
        // length word) followed by the encoded tuples.
        var elementOffsets = ""
        var runningOffset = calls.count * 32 // bytes
        for tuple in encodedTuples {
            elementOffsets += word(runningOffset)
            runningOffset += tuple.count / 2
        }

        let arrayBody = elementOffsets + encodedTuples.joined()
        return "0x"
            + aggregate3Selector
            + word(0x20)            // offset to the single dynamic argument (the array)
            + word(calls.count)     // array length
            + arrayBody
    }

    // MARK: - Decode

    /// Decodes the `(bool success, bytes returnData)[]` returned by `aggregate3`,
    /// in the same order the calls were built. Each entry is the `uint256` parsed
    /// from `returnData`, or `nil` when the sub-call failed or returned fewer than
    /// 32 bytes — the caller maps `nil` to a `0` balance, reproducing today's
    /// per-call "balance check failed → 0" fallback.
    static func decodeAggregate3Results(hex: String) -> [BigInt?] {
        guard let data = Data(hexString: hex.stripHexPrefix()) else { return [] }
        let bytes = [UInt8](data)
        let word = 32

        func uint(at offset: Int) -> BigUInt? {
            guard offset >= 0, offset + word <= bytes.count else { return nil }
            return BigUInt(Data(bytes[offset..<offset + word]))
        }
        // Offsets must point inside the response; bounding them also prevents an
        // Int overflow trap on a malformed (huge) offset word.
        func offset(_ value: BigUInt?) -> Int? {
            guard let value, value <= BigUInt(bytes.count) else { return nil }
            return Int(value)
        }

        // Outer return is a single dynamic value (Result[]): word[0] is the offset
        // to the array, then the array length, then the per-element offsets.
        guard let arrayOffset = offset(uint(at: 0)),
              let countBig = uint(at: arrayOffset),
              countBig <= BigUInt(bytes.count / word) else {
            return []
        }
        let count = Int(countBig)
        let headBase = arrayOffset + word
        // The element-offset head (one word per result) must fit entirely within
        // the payload. The count guard above ignores `arrayOffset`, so a header
        // pointing near EOF would otherwise produce `count` nils that the caller
        // reads as an all-zero success instead of a malformed batch to fall back
        // from. Reject it here so the per-token path takes over.
        guard headBase <= bytes.count,
              count <= (bytes.count - headBase) / word else {
            return []
        }

        var results: [BigInt?] = []
        results.reserveCapacity(count)

        for index in 0..<count {
            guard let elementOffset = offset(uint(at: headBase + index * word)) else {
                results.append(nil)
                continue
            }
            let tupleStart = headBase + elementOffset
            // Tuple is (bool success, bytes returnData): head is success and the
            // offset to the bytes (always 0x40 = 2 words).
            guard let successWord = uint(at: tupleStart),
                  let bytesRelOffset = offset(uint(at: tupleStart + word)) else {
                results.append(nil)
                continue
            }
            let bytesStart = tupleStart + bytesRelOffset
            guard successWord != 0,
                  let returnLength = uint(at: bytesStart),
                  returnLength >= 32,
                  let value = uint(at: bytesStart + word) else {
                results.append(nil)
                continue
            }
            results.append(BigInt(value))
        }

        return results
    }

    // MARK: - Hex helpers

    private static func word(_ value: Int) -> String {
        String(value, radix: 16).paddingLeft(toLength: hexWordLength, withPad: "0")
    }

    private static func paddedAddress(_ address: String) -> String {
        address.stripHexPrefix().lowercased().paddingLeft(toLength: hexWordLength, withPad: "0")
    }

    private static func rightPadded(_ hex: String) -> String {
        let clean = hex.stripHexPrefix().lowercased()
        let remainder = clean.count % hexWordLength
        guard remainder != 0 else { return clean }
        return clean + String(repeating: "0", count: hexWordLength - remainder)
    }
}
