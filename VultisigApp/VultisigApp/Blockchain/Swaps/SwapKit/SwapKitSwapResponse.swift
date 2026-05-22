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
    /// Optional top-level destination-tag field. Defensive: SwapKit's docs
    /// don't list this for XRP routes today (NEAR allocates a per-route
    /// ephemeral r-address, so no tag is needed), but the silent-misroute
    /// failure mode for XRP-to-shared-vault transfers is severe enough that
    /// we accept a tag from three sources at decode time and pick the first
    /// non-nil via `resolvedDestinationTag`.
    let destinationTag: UInt64?

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

    /// XRP destination-tag resolution. Precedence: top-level field beats
    /// `meta.destinationTag` beats the `?dt=` / `|` suffix on `targetAddress`.
    /// Returns `nil` if no source surfaces one — the cosigning peer then
    /// builds a tag-less Payment, which is the correct behaviour for NEAR-
    /// allocated ephemeral deposit addresses.
    var resolvedDestinationTag: UInt64? {
        if let tag = destinationTag { return tag }
        if let tag = meta.destinationTag { return tag }
        return Self.extractTagSuffix(from: targetAddress).tag
    }

    /// XRP target-address stripped of any `?dt=…` or `|…` destination-tag
    /// suffix. For non-XRP responses (no suffix present), returns
    /// `targetAddress` verbatim. Defensive — every probe today returns a
    /// bare r-address.
    var resolvedTargetAddress: String {
        Self.extractTagSuffix(from: targetAddress).address
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
        case destinationTag
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
        // SwapKit may surface a numeric `destinationTag` (rare) or a string-
        // wrapped one (defensive — `meta.affiliateFee` arrives as a string
        // even though it's numeric semantically, so accept both shapes).
        if let intTag = try? container.decodeIfPresent(UInt64.self, forKey: .destinationTag) {
            destinationTag = intTag
        } else if let stringTag = try? container.decodeIfPresent(String.self, forKey: .destinationTag),
                  let parsed = UInt64(stringTag) {
            destinationTag = parsed
        } else {
            destinationTag = nil
        }
        tx = try Self.decodeTx(meta: meta, sellAsset: sellAsset, container: container)
    }

    /// Discriminate the PSBT shape by source chain. SwapKit's wire surface
    /// is the same uniform base64 PSBT for every UTXO chain, but the inner
    /// unsigned-tx body differs (segwit BIP-144 for BTC/LTC, legacy
    /// pre-segwit for DOGE/BCH/DASH, Sapling-v4 for ZEC). The decoder picks
    /// the right `SwapKitTx` case from the `sellAsset` prefix so the
    /// keysign dispatcher can route directly to the per-chain signer.
    /// Asset-prefix matching is case-insensitive to absorb any future
    /// `DOGE.DOGE` vs `Doge.doge` drift in upstream catalogs.
    private static func psbtCase(forSellAsset sellAsset: String, base64: String) -> SwapKitTx {
        let chain = sellAsset.uppercased().split(separator: ".").first.map(String.init) ?? ""
        switch chain {
        case "DOGE":
            return .dogecoinPsbt(base64: base64)
        case "BCH":
            return .bitcoinCashPsbt(base64: base64)
        case "DASH":
            return .dashPsbt(base64: base64)
        case "ZEC":
            return .zcashPsbt(base64: base64)
        default:
            // BTC + LTC + anything else PSBT-shaped. LTC reuses the BTC
            // segwit signer (its addresses are P2WPKH / P2SH-P2WPKH —
            // `SwapKitBTCSigner.classifyScript` accepts both).
            return .psbt(base64: base64)
        }
    }

    /// Split a `?dt=12345` or `|12345` suffix off an XRP target address.
    /// Returns the bare r-address plus the parsed tag (or `nil`). Defensive —
    /// no probe today returns a suffix, but the silent-misroute failure mode
    /// is severe enough to absorb the ~20 lines of decoder.
    private static func extractTagSuffix(from address: String) -> (address: String, tag: UInt64?) {
        // `?dt=` form: `rXyz?dt=12345`
        if let q = address.firstIndex(of: "?") {
            let suffix = address[address.index(after: q)...]
            // Accept `dt=` (most likely) or any parameter set whose first
            // key is `dt`. Anything else falls through to "no tag".
            if suffix.hasPrefix("dt=") {
                let tagPart = suffix.dropFirst(3)
                if let tag = UInt64(tagPart) {
                    return (String(address[..<q]), tag)
                }
            }
        }
        // `|` form: `rXyz|12345`
        if let pipe = address.firstIndex(of: "|") {
            let suffix = address[address.index(after: pipe)...]
            if let tag = UInt64(suffix) {
                return (String(address[..<pipe]), tag)
            }
        }
        return (address, nil)
    }

    private static func decodeTx(
        meta: SwapKitSwapResponseMeta,
        sellAsset: String,
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
            // UTXO source: SwapKit returns the unsigned PSBT as a single
            // base64 string in `tx` (~480 chars, magic prefix `cHNidP8B...`).
            // Same wire shape across every UTXO chain — only the inner
            // unsigned-tx body differs (segwit P2WPKH for BTC/LTC, legacy
            // P2PKH for DOGE/BCH/DASH, Sapling-v4 for ZEC). Discriminate on
            // the source chain at decode time so the keysign dispatcher
            // routes to the right signer without grovelling around the PSBT
            // body bytes.
            let base64 = try container.decode(String.self, forKey: .tx)
            return psbtCase(forSellAsset: sellAsset, base64: base64)
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
            // Cardano source. Two live shapes observed in the wild:
            //   1. Deposit-only (legacy): `tx` is null or absent. Vultisig
            //      builds a plain ADA transfer to `targetAddress` for
            //      `sellAmount` via the existing Cardano send path.
            //   2. Pre-built (current): `tx` is a hex-encoded unsigned CBOR
            //      transaction envelope. SwapKit has already done UTXO
            //      selection, change splitting, and fee computation server-
            //      side — we sign the bytes verbatim (re-deriving them would
            //      change the txID, which NEAR Intents uses for route
            //      tracking).
            //
            // `CARDANO` was the original wire txType; upstream switched live
            // to `CBOR` (the chain's native serialisation format) without
            // versioning the change. Accept both — a future flip back to
            // `CARDANO` shouldn't break us either.
            if container.contains(.tx) {
                if try container.decodeNil(forKey: .tx) {
                    return .cardano
                }
                // Hex string → pre-built CBOR transaction. Strip an optional
                // `0x` prefix defensively — SwapKit's observed responses ship
                // bare hex, but hex-with-prefix is the standard EVM convention
                // and a wire flip is cheap to absorb.
                if let hexString = try? container.decode(String.self, forKey: .tx) {
                    let stripped = hexString.stripHexPrefix()
                    if let cbor = Data(hexString: stripped) {
                        return .cardanoPrebuilt(cbor: cbor)
                    }
                    // Hex string that doesn't parse as hex — fall through to
                    // `.unsupported` rather than silently dropping the body.
                    let raw = try container.decode(SwapKitRawJSON.self, forKey: .tx)
                    return .unsupported(txType: meta.txType, raw: raw)
                }
                // Forward-compat: some future provider may start returning a
                // structured Cardano tx (JSON object). Surface as
                // `.unsupported` so the decoder doesn't silently drop the
                // payload — the keysign dispatcher will throw with the
                // txType in the message.
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
        case "XRP", "RIPPLE":
            // XRP source: deposit-only flow modelled on Cardano. NEAR Intents
            // allocates a per-route ephemeral r-address at `targetAddress` —
            // Vultisig builds a plain XRP Payment to that address for
            // `sellAmount` via the existing `RippleHelper`. SwapKit's docs
            // explicitly reject X-addresses and don't document a
            // `destinationTag` field, but the three-source defensive
            // resolution (top-level field → meta → suffix on targetAddress)
            // makes a future Chainflip-style shared-vault flip non-breaking.
            // Accept `XRP` (canonical) and `RIPPLE` (defensive — SwapKit has
            // form for switching between asset names mid-route).
            return .rippleDepositOnly
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
    /// Cardano source — pre-built CBOR flow. SwapKit has performed UTXO
    /// selection, change splitting, and fee computation server-side and
    /// returns the unsigned Cardano transaction envelope as hex CBOR (item
    /// 0 of the top-level array is the transaction body Vultisig signs).
    /// Re-deriving the body locally would change the tx_id; NEAR Intents
    /// tracks routes by that hash, so we sign the bytes verbatim.
    case cardanoPrebuilt(cbor: Data)
    /// Sui source — base64-encoded pre-built programmable transaction block
    /// (PTB). Signing requires a greenfield "sign pre-built PTB" path
    /// (existing Pay / PaySui flows won't accept a serialized PTB). Deferred
    /// to the consolidated signing PR.
    case sui(base64: String)
    /// TRON source — TronWeb-shaped object with `txID`, `rawData`, and
    /// `rawDataHex`. The `raw_data_hex` is the canonical input to WalletCore
    /// Tron signing; the rest is kept verbatim for the verify screen.
    case tron(SwapKitTronTx)
    /// XRP source — deposit-only flow. SwapKit hands us an ephemeral r-address
    /// at `targetAddress` and (optionally) a `destinationTag`; Vultisig
    /// builds a plain XRP Payment to that address for `sellAmount` via the
    /// existing `RippleHelper`. No transaction body to sign — same model as
    /// `.cardano`.
    case rippleDepositOnly
    /// DOGE source — legacy P2PKH PSBT. Same `meta.txType: "PSBT"` wire as
    /// BTC, but inputs are P2PKH (DOGE has no segwit). Signed via WalletCore
    /// `CoinType.dogecoin` + frozen `BitcoinTransactionPlan` (no replanner
    /// — preserves the broadcast tx_id NEAR Intents tracks the route by).
    case dogecoinPsbt(base64: String)
    /// BCH source — legacy P2PKH PSBT. Same structure as DOGE; BCH adds
    /// SIGHASH_FORKID natively via `BitcoinScript.hashTypeForCoin(.bitcoinCash)`.
    case bitcoinCashPsbt(base64: String)
    /// DASH source — legacy P2PKH PSBT (DASH has no segwit). Same structure
    /// as DOGE/BCH; signed via `CoinType.dash`.
    case dashPsbt(base64: String)
    /// ZEC source — Sapling-v4 transparent PSBT. Inputs are P2PKH; the
    /// unsigned-tx body carries `nVersionGroupId` + `expiryHeight` + zeroed
    /// shielded fields. Signed via `CoinType.zcash` with the Sapling
    /// branchID (`0x76b809bb` LE) for ZIP-243 sighash.
    case zcashPsbt(base64: String)
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
    /// Optional XRP destination tag surfaced via the meta block (second of
    /// three resolution sources — see `SwapKitSwapResponse.resolvedDestinationTag`).
    let destinationTag: UInt64?

    private enum CodingKeys: String, CodingKey {
        case txType
        case approvalAddress
        case isFastQuote
        case isRefreshed
        case priceImpact
        case affiliate
        case affiliateFee
        case destinationTag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        txType = try container.decode(String.self, forKey: .txType)
        approvalAddress = try container.decodeIfPresent(String.self, forKey: .approvalAddress)
        isFastQuote = try container.decodeIfPresent(Bool.self, forKey: .isFastQuote)
        isRefreshed = try container.decodeIfPresent(Bool.self, forKey: .isRefreshed)
        priceImpact = try container.decodeIfPresent(Double.self, forKey: .priceImpact)
        affiliate = try container.decodeIfPresent(String.self, forKey: .affiliate)
        affiliateFee = try container.decodeIfPresent(String.self, forKey: .affiliateFee)
        if let intTag = try? container.decodeIfPresent(UInt64.self, forKey: .destinationTag) {
            destinationTag = intTag
        } else if let stringTag = try? container.decodeIfPresent(String.self, forKey: .destinationTag),
                  let parsed = UInt64(stringTag) {
            destinationTag = parsed
        } else {
            destinationTag = nil
        }
    }
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
