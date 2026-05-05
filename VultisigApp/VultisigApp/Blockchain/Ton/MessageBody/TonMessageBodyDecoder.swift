//
//  TonMessageBodyDecoder.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-message-body-decoder")

/// Decode the body BOC of a TON internal message into a structured intent.
///
/// Mirrors `decodeTonMessageBody` in the Vultisig SDK (`vultisig-sdk/packages/
/// core/chain/chains/ton/messageBody/decode.ts`). Returns `nil` when the
/// payload is empty, not a parseable BOC, has no opcode header, or carries
/// an opcode this decoder doesn't yet handle — callers should fall back to
/// displaying the raw TON transfer.
///
/// **Router binding.** Opcodes are contract-local in TON, so an attacker can
/// craft a body whose leading 32 bits collide with a known DEX swap opcode.
/// To prevent the keysign UI from labeling such a body as a "swap":
///
/// - `dedustNativeSwap` is dispatched only when `outerDestination` is a
///   known DeDust **native vault** (NOT the factory).
/// - `ptonTransfer` (STON.fi v2 TON-side swap) is dispatched only when
///   `outerDestination` is a known STON.fi v2 pTON wallet.
/// - STON.fi v2 jetton-swap detection inside `jettonTransfer` is gated on
///   the inner `destination` field being a known STON.fi v2 router.
///
/// DeDust jetton-swap detection is intentionally not provided — DeDust vaults
/// are per-jetton and not statically enumerable.
///
/// Note: dApps sometimes prefix a jetton transfer body with an empty 32-bit
/// "text comment" header (op = 0). In that case, we look at the next 32 bits.
enum TonMessageBodyDecoder {

    static func decode(payload: String?, outerDestination: String?) -> TonMessageBodyIntent? {
        guard let base64 = TonBocParser.payloadToBase64(payload) else { return nil }
        let cell: TonCell
        do {
            cell = try TonBocParser.parse(base64: base64)
        } catch {
            return nil
        }
        let slice = cell.beginParse()
        guard slice.remainingBits >= 32 else { return nil }
        let op: UInt32
        do {
            op = UInt32(try slice.loadUInt(bits: 32))
        } catch {
            return nil
        }

        if op == 0 {
            // Some dApps prefix a jetton/NFT transfer with a 0x00000000
            // "text comment" header. Peel one layer and re-dispatch.
            guard slice.remainingBits >= 32 else { return nil }
            let nestedOp: UInt32
            do {
                nestedOp = UInt32(try slice.loadUInt(bits: 32))
            } catch {
                return nil
            }
            return dispatch(op: nestedOp, slice: slice, outerDestination: outerDestination)
        }

        return dispatch(op: op, slice: slice, outerDestination: outerDestination)
    }

    private static func dispatch(
        op: UInt32,
        slice: TonSlice,
        outerDestination: String?
    ) -> TonMessageBodyIntent? {
        switch op {
        case TonOpcode.jettonTransfer:
            return parseJettonTransfer(slice: slice)
        case TonOpcode.nftTransfer:
            return parseNftTransfer(slice: slice)
        case TonOpcode.excesses:
            return parseExcesses(slice: slice)
        case TonOpcode.ptonTransfer:
            guard isKnownRouter(address: outerDestination, in: TonKnownRouters.stonfiV2PtonWallets) else {
                return nil
            }
            return parsePtonTransferSwap(slice: slice)
        case TonOpcode.dedustNativeSwap:
            guard isKnownRouter(address: outerDestination, in: TonKnownRouters.dedustNativeVaults) else {
                return nil
            }
            return parseDedustNativeSwap(slice: slice)
        default:
            return nil
        }
    }

    // MARK: - Jetton

    private static func parseJettonTransfer(slice: TonSlice) -> TonMessageBodyIntent? {
        return safeDecode {
            let queryId = try slice.loadBigUInt(bits: 64)
            let amount = try slice.loadCoins()
            let destination = try slice.loadAddress()
            let responseDestination = try slice.loadMaybeAddress()
            // custom_payload: Maybe ^Cell — load and discard.
            _ = try slice.loadMaybeRef()
            let forwardTonAmount = try slice.loadCoins()
            let forwardPayload = try loadForwardPayload(slice: slice)

            // STON.fi v2 swap classification is gated on the jetton transfer's
            // inner destination being a known STON.fi v2 router. DeDust jetton
            // swaps are intentionally not classified — DeDust uses one vault
            // per jetton, and the vault set is not statically enumerable.
            if let payload = forwardPayload,
               isKnownRouter(address: destination, in: TonKnownRouters.stonfiV2Routers),
               let swap = parseStonfiV2Swap(
                   cell: payload,
                   offerAsset: .jetton,
                   offerAmount: amount
               ) {
                return .swap(swap)
            }

            return .jettonTransfer(.init(
                queryId: decimalString(fromBigEndian: queryId),
                amount: amount,
                destination: destination,
                responseDestination: responseDestination,
                forwardTonAmount: forwardTonAmount
            ))
        }
    }

    private static func parseNftTransfer(slice: TonSlice) -> TonMessageBodyIntent? {
        return safeDecode {
            let queryId = try slice.loadBigUInt(bits: 64)
            let newOwner = try slice.loadAddress()
            let responseDestination = try slice.loadMaybeAddress()
            _ = try slice.loadMaybeRef()
            let forwardAmount = try slice.loadCoins()
            // forward_payload:(Either Cell ^Cell) — required by TEP-62; we
            // don't surface its content but must consume it to reject bodies
            // truncated before this field.
            _ = try loadForwardPayload(slice: slice)
            return .nftTransfer(.init(
                queryId: decimalString(fromBigEndian: queryId),
                newOwner: newOwner,
                responseDestination: responseDestination,
                forwardAmount: forwardAmount
            ))
        }
    }

    private static func parseExcesses(slice: TonSlice) -> TonMessageBodyIntent? {
        return safeDecode {
            let queryId = try slice.loadBigUInt(bits: 64)
            return .excesses(queryId: decimalString(fromBigEndian: queryId))
        }
    }

    // MARK: - Swaps

    private static func parsePtonTransferSwap(slice: TonSlice) -> TonMessageBodyIntent? {
        return safeDecode {
            _ = try slice.loadBigUInt(bits: 64) // query_id
            let offerAmount = try slice.loadCoins()
            _ = try slice.loadAddress() // refund_address (consumed; SDK reads but ignores)
            guard let forwardPayload = try loadForwardPayload(slice: slice) else { return nil }
            guard let swap = parseStonfiV2Swap(
                cell: forwardPayload,
                offerAsset: .ton,
                offerAmount: offerAmount
            ) else { return nil }
            return .swap(swap)
        }
    }

    private static func parseStonfiV2Swap(
        cell: TonCell,
        offerAsset: TonMessageBodyIntent.Swap.OfferAsset,
        offerAmount: String
    ) -> TonMessageBodyIntent.Swap? {
        return safeDecode {
            let inner = cell.beginParse()
            guard inner.remainingBits >= 32 else { return nil }
            let op = UInt32(try inner.loadUInt(bits: 32))
            guard op == TonOpcode.stonfiV2Swap else { return nil }

            let targetAddress = try inner.loadAddress()
            let refundAddress = try inner.loadAddress()
            let excessesAddress = try inner.loadAddress()
            _ = try inner.loadBigUInt(bits: 64) // deadline / tx ts

            // additional_data ref shape (STON.fi v2 swap body — same layout
            // used by both `createSwapBody` and `createCrossSwapBody`):
            //   min_out:Coins
            //   receiver:MsgAddressInt
            //   custom_payload_fwd_gas:Coins
            //   custom_payload:(Maybe ^Cell)
            //   refund_fwd_gas:Coins
            //   refund_payload:(Maybe ^Cell)
            //   referral_value:uint16
            //   referral_address:MsgAddressInt (addr_none allowed)
            //
            // We must consume ALL fields — without them, a body with a valid
            // prefix and garbage tail decodes as a "swap" because parsing
            // would stop after `receiver`. Reading every field turns "garbage
            // tail" into a parse error caught by the safeDecode wrapper.
            let additionalData = try inner.loadRef().beginParse()
            let minOut = try additionalData.loadCoins()
            let receiverAddress = try additionalData.loadAddress()
            _ = try additionalData.loadCoins()      // custom_payload_fwd_gas
            _ = try additionalData.loadMaybeRef()   // custom_payload
            _ = try additionalData.loadCoins()      // refund_fwd_gas
            _ = try additionalData.loadMaybeRef()   // refund_payload
            _ = try additionalData.loadUInt(bits: 16) // referral_value (BPS)
            _ = try additionalData.loadMaybeAddress() // referral_address

            return TonMessageBodyIntent.Swap(
                provider: .stonfi,
                offerAsset: offerAsset,
                offerAmount: offerAmount,
                minOut: minOut,
                receiverAddress: receiverAddress,
                refundAddress: refundAddress,
                excessesAddress: excessesAddress,
                targetAddress: targetAddress
            )
        }
    }

    /// Decode a DeDust native-TON swap. DeDust jetton-side swaps are
    /// intentionally not classified — DeDust uses one vault per jetton and
    /// the vault set isn't statically enumerable.
    private static func parseDedustNativeSwap(slice: TonSlice) -> TonMessageBodyIntent? {
        return safeDecode {
            _ = try slice.loadBigUInt(bits: 64) // query_id
            let offerAmount = try slice.loadCoins()

            // SwapStepParams: target:MsgAddressInt kind:SwapKind limit:Coins next:(Maybe ^SwapStep)
            let targetAddress = try slice.loadAddress()
            // SwapKind is a 1-bit prefix: given_in$0 | given_out$1.
            // given_out is "Not implemented." per DeDust docs — fail closed
            // so a body with garbage in the SwapKind slot doesn't surface as
            // `swap`.
            let kind = try slice.loadBit()
            guard !kind else { return nil }
            let minOut = try slice.loadCoins()
            _ = try slice.loadMaybeRef()

            // SwapParams: deadline:uint32 recipient:(Maybe MsgAddress)
            //             referral:(Maybe MsgAddress) fulfillPayload:(Maybe ^Cell)
            //             rejectPayload:(Maybe ^Cell)
            _ = try slice.loadUInt(bits: 32)
            let receiverAddress = try slice.loadMaybeAddress()
            _ = try slice.loadMaybeAddress()
            _ = try slice.loadMaybeRef()
            _ = try slice.loadMaybeRef()

            return .swap(.init(
                provider: .dedust,
                offerAsset: .ton,
                offerAmount: offerAmount,
                minOut: minOut,
                receiverAddress: receiverAddress,
                refundAddress: nil,
                excessesAddress: nil,
                targetAddress: targetAddress
            ))
        }
    }

    // MARK: - Helpers

    private static func loadForwardPayload(slice: TonSlice) throws -> TonCell? {
        let isRef = try slice.loadBit()
        if isRef {
            return try slice.loadRef()
        }
        // Inline forward payload: the rest of the slice IS the payload. Pack
        // the unread tail (bits + refs) into a synthetic cell so swap
        // decoding can re-parse it from the start without losing nested
        // refs.
        guard slice.remainingBits >= 32 else { return nil }
        return slice.asRemainingCell()
    }

    private static func isKnownRouter(address: String?, in routerSet: Set<String>) -> Bool {
        guard let address, !address.isEmpty else { return false }
        guard let normalized = TONAddressConverter.toUserFriendly(
            address: address,
            bounceable: true,
            testnet: false
        ) else { return false }
        return routerSet.contains(normalized)
    }

    /// Catch any thrown parse error and surface it as `nil`. Mirrors the
    /// SDK's `safeDecode` — body decoders fail closed on truncation rather
    /// than crashing the keysign UI.
    private static func safeDecode<T>(_ work: () throws -> T?) -> T? {
        do {
            return try work()
        } catch {
            return nil
        }
    }
}
