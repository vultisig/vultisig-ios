//
//  SwapKitSwapResponse.swift
//  VultisigApp
//
//  Decodable models for the V3 `/v3/swap` response. The `tx` field shape is
//  driven by `meta.txType` — Phase 1 ships typed `EVM` and `SOLANA` variants,
//  Phase 2 adds `PSBT` (Bitcoin), and Phase 3 promotes `TON` / `CARDANO` /
//  `SUI` / `TRON` into typed cases. Everything else still stashes through the
//  passthrough JSON blob until its own per-chain phase promotes it.
//

import Foundation

struct SwapKitSwapResponse: Decodable, Hashable {
    let swapId: String
    let routeId: String
    let providers: [String]
    let sellAsset: String
    let buyAsset: String
    let sellAmount: String
    let expectedBuyAmount: String
    let expectedBuyAmountMaxSlippage: String
    let sourceAddress: String
    let destinationAddress: String
    let targetAddress: String
    let inboundAddress: String?
    let meta: SwapKitSwapResponseMeta
    let tx: SwapKitTx
    let approvalTx: SwapKitApprovalTx?
    let fees: [SwapKitFee]
    let warnings: [SwapKitWarning]?

    /// Some chains (Cardano) return responses without a `tx` field at all —
    /// see `SwapKitTx.cardano`. The `Hashable` synthesis still works because
    /// `tx` always exists as a value; `.cardano` is the sentinel for "no
    /// transaction body returned".

    /// First provider in the route — used as the verify-screen sub-provider
    /// tag ("via Chainflip", "via NEAR Intents"). Phase 1 ships single-hop
    /// only, so this string is unambiguous.
    var subProvider: String {
        providers.first ?? "SwapKit"
    }

    private enum CodingKeys: String, CodingKey {
        case swapId
        case routeId
        case providers
        case sellAsset
        case buyAsset
        case sellAmount
        case expectedBuyAmount
        case expectedBuyAmountMaxSlippage
        case sourceAddress
        case destinationAddress
        case targetAddress
        case inboundAddress
        case meta
        case tx
        case approvalTx
        case fees
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        swapId = try container.decode(String.self, forKey: .swapId)
        routeId = try container.decode(String.self, forKey: .routeId)
        providers = try container.decode([String].self, forKey: .providers)
        sellAsset = try container.decode(String.self, forKey: .sellAsset)
        buyAsset = try container.decode(String.self, forKey: .buyAsset)
        sellAmount = try container.decode(String.self, forKey: .sellAmount)
        expectedBuyAmount = try container.decode(String.self, forKey: .expectedBuyAmount)
        expectedBuyAmountMaxSlippage = try container.decode(String.self, forKey: .expectedBuyAmountMaxSlippage)
        sourceAddress = try container.decode(String.self, forKey: .sourceAddress)
        destinationAddress = try container.decode(String.self, forKey: .destinationAddress)
        targetAddress = try container.decode(String.self, forKey: .targetAddress)
        inboundAddress = try container.decodeIfPresent(String.self, forKey: .inboundAddress)
        meta = try container.decode(SwapKitSwapResponseMeta.self, forKey: .meta)
        approvalTx = try container.decodeIfPresent(SwapKitApprovalTx.self, forKey: .approvalTx)
        // `decodeIfPresent` (not `try?`) so a malformed `fees` payload
        // surfaces as a decode error instead of silently flattening to an
        // empty array — silent collapse would hide an upstream wire change
        // and leave `inboundFee` returning nil at quote time.
        fees = try container.decodeIfPresent([SwapKitFee].self, forKey: .fees) ?? []
        warnings = try container.decodeIfPresent([SwapKitWarning].self, forKey: .warnings)
        tx = try Self.decodeTx(meta: meta, container: container)
    }

    private static func decodeTx(
        meta: SwapKitSwapResponseMeta,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> SwapKitTx {
        let txType = meta.txType.uppercased()
        switch txType {
        case "EVM":
            let evm = try container.decode(SwapKitEvmTx.self, forKey: .tx)
            return .evm(evm)
        case "SOLANA", "SERIALIZED_BASE64":
            // SwapKit upstream switched live from `meta.txType: "SOLANA"`
            // to `"SERIALIZED_BASE64"` (the generic name for base64-encoded
            // pre-built transaction bytes) without versioning the change.
            // Same wire shape — `tx` is a single base64 string. Accept both
            // so a flip back doesn't break us either.
            let base64 = try container.decode(String.self, forKey: .tx)
            return .solana(base64: base64)
        case "PSBT":
            // Bitcoin source: SwapKit returns the unsigned PSBT as a single
            // base64 string in `tx` (~480 chars, magic prefix `cHNidP8B...`).
            // No nested object — `tx` is the bare string, mirroring the
            // Solana shape. The keysign-side dispatcher base64-decodes into
            // the proto `tx_payload` bytes field for cross-device transit.
            let base64 = try container.decode(String.self, forKey: .tx)
            return .psbt(base64: base64)
        case "TON":
            // TON source: SwapKit returns `tx` as a single-element array of
            // `{address, amount}` objects. `amount` is raw nano-TON (1e9 =
            // 1 TON). The deposit address matches `targetAddress`. The
            // keysign-side dispatcher JSON-encodes the array verbatim into
            // `tx_payload` bytes for cross-device transit, then rebuilds a
            // plain TON transfer to the deposit address with the raw amount.
            let transfers = try container.decode([SwapKitTonTransfer].self, forKey: .tx)
            return .ton(transfers)
        case "CARDANO", "CBOR":
            // Cardano source: deposit-only flow. SwapKit returns no
            // transaction body — `tx` is null at the wire, and in observed
            // fixtures the key is sometimes omitted entirely. Vultisig
            // builds a plain ADA transfer to `targetAddress` for
            // `sellAmount` via the existing Cardano send path. Tolerate
            // both shapes: `tx: null` and `tx` absent.
            //
            // `CARDANO` was the original wire value at integration time;
            // upstream switched live to `CBOR` (Cardano's native wire
            // serialisation format) without versioning the change.
            // Accept both so a flip back doesn't break us either.
            if container.contains(.tx) {
                if try container.decodeNil(forKey: .tx) {
                    return .cardano
                }
                // Forward-compat: some future provider may start returning a
                // structured Cardano tx. Surface as `.unsupported` so the
                // decoder doesn't silently drop the payload.
                let raw = try container.decode(SwapKitRawJSON.self, forKey: .tx)
                return .unsupported(txType: meta.txType, raw: raw)
            }
            return .cardano
        case "SUI":
            // Sui source: SwapKit returns a base64-encoded pre-built Sui
            // programmable transaction block (PTB), ~5KB. The keysign-side
            // dispatcher base64-decodes into bytes for cross-device transit.
            // Signing is greenfield (existing Pay/PaySui paths don't accept a
            // pre-built PTB) — deferred to the consolidated signing PR.
            let base64 = try container.decode(String.self, forKey: .tx)
            return .sui(base64: base64)
        case "TRON":
            // TRON source: SwapKit returns a TronWeb-shaped object with
            // `{txID, raw_data {...}, raw_data_hex, visible?}`. We model the
            // top-level fields strictly and stash `raw_data` through a JSON
            // passthrough so unexpected sub-fields don't break decoding
            // (`raw_data` shape varies by Tron contract type). The
            // keysign-side dispatcher JSON-encodes the canonical TronWeb
            // object verbatim into `tx_payload` bytes for cross-device
            // transit.
            let tron = try container.decode(SwapKitTronTx.self, forKey: .tx)
            return .tron(tron)
        default:
            // Phase 3 types EVM + Solana + PSBT + TON + CARDANO + SUI + TRON.
            // Anything else still stashes through the raw-JSON passthrough so
            // the keysign dispatcher can surface a descriptive "not yet
            // supported" error rather than silently misdecoding.
            let raw = try container.decode(SwapKitRawJSON.self, forKey: .tx)
            return .unsupported(txType: meta.txType, raw: raw)
        }
    }
}

/// `tx` discriminated union. `unsupported` carries the raw JSON so future
/// phases can promote it to a typed case without changing the wire surface.
enum SwapKitTx: Hashable {
    case evm(SwapKitEvmTx)
    case solana(base64: String)
    /// Bitcoin source — base64-encoded PSBT string. Same wire shape across
    /// every SwapKit BTC provider observed in the Phase 0 spike (NEAR,
    /// FLASHNET, GARDEN; Chainflip BTC validated structurally only).
    case psbt(base64: String)
    /// TON source — single-element array of `{address, amount}` transfers.
    /// `amount` is raw nano-TON. Deposit address matches `targetAddress`.
    /// No memo. Built from a plain TON transfer via the existing send path.
    case ton([SwapKitTonTransfer])
    /// Cardano source — deposit-only flow. SwapKit returns `tx: null` (and
    /// some responses omit `tx` entirely). Vultisig builds a plain ADA
    /// transfer to `targetAddress` for `sellAmount` via the existing
    /// Cardano send path. No CBOR construction, no metadata.
    case cardano
    /// Sui source — base64-encoded pre-built programmable transaction block
    /// (PTB). Signing requires a greenfield "sign pre-built PTB" path
    /// (existing Pay / PaySui flows won't accept a serialized PTB). Deferred
    /// to the consolidated signing PR.
    case sui(base64: String)
    /// TRON source — TronWeb-shaped object with `txID`, `rawData`, and
    /// `rawDataHex`. The `raw_data_hex` is the canonical input to WalletCore
    /// Tron signing; the rest is kept verbatim for the verify screen.
    case tron(SwapKitTronTx)
    case unsupported(txType: String, raw: SwapKitRawJSON)
}

/// TON `tx[]` element. `amount` is raw nano-TON (decimal string, NOT TON
/// units). SwapKit always returns a single-element array in the Phase 0
/// spike — the array shape is preserved so multi-output transfers (if SwapKit
/// ever exposes them) decode cleanly.
struct SwapKitTonTransfer: Codable, Hashable {
    let address: String
    let amount: String
}

/// TRON `tx` object. We model the strict top-level shape and preserve
/// `rawData` through a JSON passthrough so the contract-specific sub-fields
/// (TriggerSmartContract / TransferContract / ...) survive intact. The
/// `rawDataHex` field is what WalletCore Tron signing consumes — that's the
/// load-bearing field for the deferred signing PR.
struct SwapKitTronTx: Codable, Hashable {
    /// Tron transaction id, hex string (sha256 of `raw_data` per Tron protocol).
    let txID: String
    /// Pre-encoded raw transaction bytes, hex string. Canonical input to
    /// WalletCore Tron signing.
    let rawDataHex: String
    /// Visibility flag (TronWeb addresses encoded as base58 when true).
    /// Optional — not all providers populate it.
    let visible: Bool?
    /// Nested `raw_data` object. Sub-fields (`contract[]`, `ref_block_*`,
    /// `fee_limit`, `expiration`, `timestamp`) vary by contract type, so we
    /// stash them through `SwapKitJSONValue` to preserve unexpected shapes
    /// without locking the schema down.
    let rawData: SwapKitJSONValue

    private enum CodingKeys: String, CodingKey {
        case txID
        case rawData = "raw_data"
        case rawDataHex = "raw_data_hex"
        case visible
    }
}

struct SwapKitEvmTx: Decodable, Hashable {
    let from: String
    let to: String
    let value: String
    let data: String
    let gas: String
    let gasPrice: String
}

/// Approval transaction. Important wire quirk: this object uses `gasLimit`
/// rather than `gas` (the main `tx` uses `gas`). Decoder normalises both into
/// the same Swift property name.
struct SwapKitApprovalTx: Decodable, Hashable {
    let to: String
    let from: String
    let value: String
    let data: String
    let gasLimit: String
    let gasPrice: String
}

struct SwapKitSwapResponseMeta: Decodable, Hashable {
    let txType: String
    let approvalAddress: String?
    let isFastQuote: Bool?
    let isRefreshed: Bool?
    let priceImpact: Double?
    let affiliate: String?
    let affiliateFee: String?
}

struct SwapKitWarning: Decodable, Hashable {
    let code: String?
    let display: String?
    let tooltip: String?
}

/// Opaque JSON passthrough. Used by `SwapKitTx.unsupported` so future per-chain
/// payload work can decode it without changing the response model.
struct SwapKitRawJSON: Decodable, Hashable {
    let data: Data

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try to decode as raw bytes by re-encoding the JSON value the decoder
        // currently points at. Falling back to "{}" lets us survive
        // malformed/unexpected shapes without aborting the whole response —
        // the keysign dispatcher will still surface "txType <x> not yet
        // supported" with the txType string, which is what the user sees.
        if let json = try? container.decode(SwapKitJSONValue.self) {
            data = (try? JSONEncoder().encode(json)) ?? Data("{}".utf8)
        } else {
            data = Data("{}".utf8)
        }
    }
}

/// Minimal JSON-value type used to preserve unsupported `tx` payloads in
/// `SwapKitTx.unsupported`. Anything decodable into Foundation types lands
/// here and re-encodes losslessly.
indirect enum SwapKitJSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SwapKitJSONValue])
    case object([String: SwapKitJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SwapKitJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: SwapKitJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
