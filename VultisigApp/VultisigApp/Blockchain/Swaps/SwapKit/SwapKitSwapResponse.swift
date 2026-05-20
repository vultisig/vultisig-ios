//
//  SwapKitSwapResponse.swift
//  VultisigApp
//
//  Decodable models for the V3 `/v3/swap` response. The `tx` field shape is
//  driven by `meta.txType` — Phase 1 ships typed `EVM` and `SOLANA` variants,
//  Phase 2 adds `PSBT` (Bitcoin), and everything else stashes through the
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
        default:
            // Phase 2 types EVM + Solana + PSBT; later phases promote TRON,
            // SUI, COSMOS, TON, CARDANO into typed cases. Until then we keep
            // the raw JSON so the keysign dispatcher can surface a descriptive
            // "not yet supported" error rather than silently misdecoding.
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
    case unsupported(txType: String, raw: SwapKitRawJSON)
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
