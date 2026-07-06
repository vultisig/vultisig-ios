//
//  TonSwapSimulator.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-swap-simulator")

/// Calls TonAPI's `/v2/events/emulate` to detect whether a TonConnect
/// transaction performs a jetton swap. Used as a fallback when the local BOC
/// decoder doesn't classify any message as a swap (e.g. DeDust jetton swaps,
/// custom DEX integrations) so the keysign UI can still surface a
/// "you're swapping" hero card with input/output amounts.
///
/// Mirrors `useTonSimulation.ts` from the Vultisig Windows codebase.
enum TonSwapSimulator {

    /// Coin metadata pair plus amounts produced by an emulated jetton swap.
    /// Amounts are decimal strings in the asset's base units, matching the
    /// `TonMessageBodyIntent.Swap` shape so callers can format with the
    /// resolved coin's `decimals`.
    struct SwapInfo: Equatable {
        let fromAmount: String
        let fromTicker: String
        let fromDecimals: Int
        let fromLogo: String
        let toAmount: String
        let toTicker: String
        let toDecimals: Int
        let toLogo: String
    }

    /// Run an emulation against the TonAPI public host and surface the first
    /// successful `JettonSwap` action, if any. Returns `nil` for any other
    /// outcome (no swap, network failure, malformed response) so the caller
    /// can fall back to the locally-decoded message panels.
    static func simulate(keysignPayload: KeysignPayload) async -> SwapInfo? {
        guard let boc = TonExternalMessageEmulator.buildEmulationBoc(keysignPayload: keysignPayload) else {
            return nil
        }

        let event: TonApiEmulateEvent
        do {
            let response = try await HTTPClient().request(
                TonPublicAPI.emulateEvent(boc: boc),
                responseType: TonApiEmulateEvent.self
            )
            event = response.data
        } catch {
            logger.error("emulateEvent failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let jettonSwap = event.actions
            .first(where: { $0.status == "ok" && $0.type == "JettonSwap" })?
            .JettonSwap else {
            return nil
        }

        return parse(jettonSwap)
    }

    private static func parse(_ action: TonApiJettonSwapAction) -> SwapInfo? {
        let tonIn = bigDecimalString(action.ton_in) ?? "0"
        let tonOut = bigDecimalString(action.ton_out) ?? "0"
        let tonIsZero: (String) -> Bool = { $0 == "0" || $0.isEmpty }

        // TON → jetton swap (e.g. STON.fi pTON, DeDust native vault). The
        // outgoing TON is in `ton_in`, the inbound jetton in
        // `jetton_master_out` + `amount_out`.
        if !tonIsZero(tonIn), let outMaster = action.jetton_master_out {
            return SwapInfo(
                fromAmount: tonIn,
                fromTicker: nativeTonTicker,
                fromDecimals: nativeTonDecimals,
                fromLogo: nativeTonLogo,
                toAmount: action.amount_out,
                toTicker: outMaster.symbol,
                toDecimals: outMaster.decimals,
                toLogo: outMaster.image ?? ""
            )
        }

        // Jetton → TON swap (jetton transfer that funnels into a DEX → TON).
        if !tonIsZero(tonOut), let inMaster = action.jetton_master_in {
            return SwapInfo(
                fromAmount: action.amount_in,
                fromTicker: inMaster.symbol,
                fromDecimals: inMaster.decimals,
                fromLogo: inMaster.image ?? "",
                toAmount: tonOut,
                toTicker: nativeTonTicker,
                toDecimals: nativeTonDecimals,
                toLogo: nativeTonLogo
            )
        }

        // Jetton → jetton swap (e.g. STON.fi v2 cross-swap, DeDust jetton
        // swap). Both sides come from the JettonSwap masters block.
        if let inMaster = action.jetton_master_in,
           let outMaster = action.jetton_master_out {
            return SwapInfo(
                fromAmount: action.amount_in,
                fromTicker: inMaster.symbol,
                fromDecimals: inMaster.decimals,
                fromLogo: inMaster.image ?? "",
                toAmount: action.amount_out,
                toTicker: outMaster.symbol,
                toDecimals: outMaster.decimals,
                toLogo: outMaster.image ?? ""
            )
        }

        return nil
    }

    private static func bigDecimalString(_ raw: TonApiNumeric?) -> String? {
        switch raw {
        case .none: return nil
        case .number(let value): return String(value)
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static let nativeTonTicker = "GRAM"
    private static let nativeTonDecimals = 9
    private static let nativeTonLogo = "gram"
}

// MARK: - TonAPI emulate response shapes

private struct TonApiEmulateEvent: Decodable {
    let actions: [TonApiAction]
}

private struct TonApiAction: Decodable {
    let type: String
    let status: String
    // swiftlint:disable:next identifier_name
    let JettonSwap: TonApiJettonSwapAction?
}

private struct TonApiJettonSwapAction: Decodable {
    let amount_in: String
    let amount_out: String
    let jetton_master_in: TonApiJettonPreview?
    let jetton_master_out: TonApiJettonPreview?
    let ton_in: TonApiNumeric?
    let ton_out: TonApiNumeric?
}

private struct TonApiJettonPreview: Decodable {
    let address: String
    let symbol: String
    let decimals: Int
    let image: String?
}

/// Some TonAPI fields are typed `int64 | string` — accept both shapes so
/// tonapi.io schema drift doesn't silently drop the swap.
private enum TonApiNumeric: Decodable {
    case number(UInt64)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(UInt64.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        // Fail the decode rather than coercing to zero — `simulate()` already
        // returns nil on errors, so an unrecognised numeric shape falls back
        // to the locally-decoded display instead of fabricating a swap with
        // 0-valued amounts.
        throw DecodingError.typeMismatch(
            TonApiNumeric.self,
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Expected UInt64 or String for TonApiNumeric"
            )
        )
    }
}
