//
//  ZcashConventionalFee.swift
//  VultisigApp
//

import Foundation

/// ZIP-317 conventional fee for a transparent-only Zcash transaction.
/// Nodes relay zero "unpaid actions" by default, so any tx paying less is
/// rejected at broadcast with "tx unpaid action limit exceeded".
///
/// Byte-parity port of the SDK's canonical implementation
/// (`packages/core/chain/chains/utxo/fee/zip317.ts`): every co-signing
/// device must derive the same fee from the same transaction shape, or the
/// MPC preimage digests diverge and keysign fails. Keep the math in lockstep
/// with the SDK when touching this file.
/// https://zips.z.cash/zip-0317
enum ZcashConventionalFee {
    static let marginalFee: Int64 = 5_000
    static let graceActions: Int64 = 2
    /// Serialized size of a signed transparent P2PKH input (ZIP-317 section 3.1).
    private static let p2pkhInputSize: Int64 = 148
    private static let inputActionSize: Int64 = 150
    private static let outputActionSize: Int64 = 34
    /// Serialized tx_out size of a P2PKH output: 8 value + 1 scriptLen + 25 script.
    private static let p2pkhOutputSize: Int64 = 34

    /// Ceiling division: smallest n such that n * divisor >= value.
    static func ceilDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
        (value + divisor - 1) / divisor
    }

    /// Minimum fee the Zcash network relays for a transparent tx of the given
    /// shape: 5,000 zats per logical action with a two-action grace window,
    /// where logical actions = max(ceil(tx_in bytes / 150), ceil(tx_out bytes / 34)).
    static func conventionalFee(inputCount: Int, outputSizes: [Int64]) -> Int64 {
        let inputActions = ceilDiv(Int64(inputCount) * p2pkhInputSize, inputActionSize)
        let outputActions = ceilDiv(outputSizes.reduce(0, +), outputActionSize)
        let logicalActions = max(inputActions, outputActions)
        return marginalFee * max(graceActions, logicalActions)
    }

    /// Serialized tx_out size of an OP_RETURN output carrying `memoSize` bytes:
    /// 8 value + scriptLen CompactSize + script (OP_RETURN + push opcode(s) + data).
    /// WalletCore's planner sizes this output as a flat ~34 bytes regardless of
    /// memo length, so longer memos make its plan undercount ZIP-317 actions.
    /// Models the push opcode (direct / PUSHDATA1 / PUSHDATA2 / PUSHDATA4) and
    /// the script-length CompactSize so long memos are not undercharged.
    static func opReturnOutputSize(memoSize: Int) -> Int64 {
        let dataSize = Int64(memoSize)

        // OP_RETURN (1 byte) + push opcode bytes for `dataSize`.
        let pushOverhead: Int64
        switch dataSize {
        case ...75: pushOverhead = 2
        case ...0xff: pushOverhead = 3
        case ...0xffff: pushOverhead = 4
        default: pushOverhead = 6
        }
        let scriptSize = pushOverhead + dataSize

        // CompactSize encoding of the script length prefix.
        let scriptLengthSize: Int64
        switch scriptSize {
        case ..<0xfd: scriptLengthSize = 1
        case ...0xffff: scriptLengthSize = 3
        case ...0xffff_ffff: scriptLengthSize = 5
        default: scriptLengthSize = 9
        }

        return 8 + scriptLengthSize + scriptSize
    }

    /// Serialized tx_out sizes for a transparent Zcash send: recipient P2PKH,
    /// optional change P2PKH (only when change is positive), and an optional
    /// OP_RETURN memo (only when `memoSize` is positive). Feed into
    /// `conventionalFee(inputCount:outputSizes:)` to size the conventional
    /// fee by real bytes.
    static func transparentOutputSizes(change: Int64, memoSize: Int) -> [Int64] {
        var sizes = [p2pkhOutputSize]
        if change > 0 {
            sizes.append(p2pkhOutputSize)
        }
        if memoSize > 0 {
            sizes.append(opReturnOutputSize(memoSize: memoSize))
        }
        return sizes
    }
}
