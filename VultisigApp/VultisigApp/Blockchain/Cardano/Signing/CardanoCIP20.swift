//
//  CardanoCIP20.swift
//  VultisigApp
//
//  Canonical CIP-20 transaction-metadata encoder for Cardano memos.
//
//  A Cardano memo is CIP-20 metadata under the registered label 674:
//
//      { 674: { "msg": [ "<chunk1>", "<chunk2>", ... ] } }
//
//  Each `msg` text chunk is at most 64 UTF-8 bytes, split on Unicode
//  codepoint boundaries (never mid-codepoint). WalletCore 4.7.0 consumes
//  these CBOR bytes via `CardanoSigningInput.auxiliaryData`: it commits
//  blake2b-256(auxDataCbor) into the tx body at map key 7
//  (auxiliary_data_hash) and embeds the bytes as element [3] of the signed
//  transaction array.
//
//  Cardano signing is MPC/TSS: every co-signing device (iOS / Android /
//  Extension) builds the input independently and the Blake2b sighash must
//  match byte-for-byte, so this encoding MUST be byte-identical across
//  platforms. It mirrors the mainnet-verified SDK encoder
//  `vultisig-sdk/packages/core/mpc/tx/compile/cardano/buildCip20AuxData.ts`
//  and the canonical primitives in `.../cardano/cip30/cardanoCborPrimitives.ts`.
//

import Foundation
import WalletCore

/// Encodes a Cardano memo as canonical CIP-20 transaction metadata (label 674).
enum CardanoCIP20 {

    /// CIP-20 limits each metadata text chunk to 64 UTF-8 bytes.
    static let maxChunkBytes = 64

    /// The CIP-20 metadata label registered on cardano.org.
    static let metadataLabel = 674

    /// Split a memo into chunks of at most 64 UTF-8 bytes, respecting UTF-8
    /// codepoint boundaries.
    ///
    /// A multi-byte codepoint straddling the 64-byte boundary is moved
    /// entirely to the next chunk rather than torn — a torn codepoint decodes
    /// to U+FFFD and corrupts the memo on-chain. UTF-8 continuation bytes have
    /// the top bits `10xxxxxx`; we walk back off them until the cut lands on a
    /// leading byte. An empty memo yields a single empty-string chunk (matches
    /// the SDK, which always emits at least one `msg` element).
    static func memoToChunks(_ memo: String) -> [String] {
        let bytes = Array(memo.utf8)
        if bytes.isEmpty { return [""] }

        var chunks: [String] = []
        var start = 0
        while start < bytes.count {
            var end = min(start + maxChunkBytes, bytes.count)

            // If we are not at the end and `end` lands on a continuation byte
            // (0b10xxxxxx), back up until the byte at `end` starts a codepoint.
            if end < bytes.count {
                while end > start, (bytes[end] & 0xC0) == 0x80 {
                    end -= 1
                }
                // Defensive: a run of >64 continuation bytes is impossible for
                // valid UTF-8 (max 4 bytes/codepoint); fall back to the raw cut
                // so we always make forward progress.
                if end == start {
                    end = min(start + maxChunkBytes, bytes.count)
                }
            }

            // Cuts always land on a codepoint boundary, so decoding a slice of
            // the (always-valid) UTF-8 bytes never fails; `?? ""` is unreachable.
            chunks.append(String(bytes: bytes[start..<end], encoding: .utf8) ?? "")
            start = end
        }
        return chunks
    }

    /// Encode the CIP-20 auxiliary data for a memo.
    ///
    /// - Returns:
    ///   - `auxDataCbor`: canonical CBOR bytes for `{ 674: { "msg": [chunks] } }`,
    ///     to be set on `CardanoSigningInput.auxiliaryData` (and, in the manual
    ///     builder, embedded as signed-tx element [3]).
    ///   - `auxDataHash`: blake2b-256 of `auxDataCbor`, which WalletCore commits
    ///     into the tx body at map key 7.
    static func buildAuxData(memo: String) -> (auxDataCbor: Data, auxDataHash: Data) {
        let chunks = memoToChunks(memo)
        let msgArray = cborArray(chunks.map { cborText($0) })
        let innerMap = cborMap([(cborText("msg"), msgArray)])
        let auxDataCbor = cborMap([(cborUint(metadataLabel), innerMap)])
        let auxDataHash = Hash.blake2b(data: auxDataCbor, size: 32)
        return (auxDataCbor, auxDataHash)
    }

    // MARK: - Minimal canonical CBOR primitives (RFC 8949 §3.1)

    /// CBOR text string (major type 3).
    private static func cborText(_ string: String) -> Data {
        let utf8 = Data(string.utf8)
        return cborHead(majorType: 3, value: utf8.count) + utf8
    }

    /// CBOR unsigned integer (major type 0).
    private static func cborUint(_ value: Int) -> Data {
        cborHead(majorType: 0, value: value)
    }

    /// CBOR array header (major type 4) followed by its items.
    private static func cborArray(_ items: [Data]) -> Data {
        var out = cborHead(majorType: 4, value: items.count)
        for item in items { out.append(item) }
        return out
    }

    /// CBOR map header (major type 5) followed by its key/value pairs.
    private static func cborMap(_ entries: [(Data, Data)]) -> Data {
        var out = cborHead(majorType: 5, value: entries.count)
        for (key, value) in entries {
            out.append(key)
            out.append(value)
        }
        return out
    }

    /// Encode the major-type + argument head in the smallest form (RFC 8949 §3.1).
    private static func cborHead(majorType: UInt8, value: Int) -> Data {
        let mt = majorType << 5
        let v = UInt64(value)
        if v < 24 {
            return Data([mt | UInt8(v)])
        } else if v < 0x100 {
            return Data([mt | 24, UInt8(v)])
        } else if v < 0x1_0000 {
            return Data([mt | 25, UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        } else if v < 0x1_0000_0000 {
            return Data([
                mt | 26,
                UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
                UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)
            ])
        } else {
            return Data([
                mt | 27,
                UInt8((v >> 56) & 0xFF), UInt8((v >> 48) & 0xFF),
                UInt8((v >> 40) & 0xFF), UInt8((v >> 32) & 0xFF),
                UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
                UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)
            ])
        }
    }
}
