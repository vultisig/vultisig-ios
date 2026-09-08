//
//  SwapKitSwapPayload.swift
//  VultisigApp
//
//  Swift-side mirror of `VSSwapKitSwapPayload` (proto field 26 in the
//  `KeysignPayload.swap_payload` oneof). Carries SwapKit-routed swaps whose
//  wire shape doesn't fit the EVM-typed `OneInchSwapPayload` — Phase 2 ships
//  the BTC PSBT path here; TRON / TON / SUI / Cardano follow in Phase 3.
//
//  The flexibility lives in `txPayload` (raw bytes, opaque to commondata)
//  and `txType` (a string discriminator the keysign dispatcher uses to pick
//  the right per-chain signer). New SwapKit chains land without a proto
//  bump — just a new `txType` value plus a per-chain signer.
//

import BigInt
import Foundation

struct SwapKitSwapPayload: Codable, Hashable {
    let fromCoin: Coin
    let toCoin: Coin
    let fromAmount: BigInt
    let toAmountDecimal: Decimal

    /// SwapKit's `meta.txType` verbatim. Drives the per-chain dispatcher:
    ///   - "PSBT"     — `txPayload` is the base64-decoded BTC PSBT
    ///   - "TRON"     — `txPayload` is the UTF-8 canonical JSON of the TronWeb tx
    ///   - "TON"      — `txPayload` is the UTF-8 canonical JSON of the transfer array
    ///   - "SUI"      — `txPayload` is the base64-decoded Sui PTB
    ///   - "CARDANO"  — `txPayload` is empty; route by `targetAddress` + `fromAmount`
    let txType: String

    /// Unsigned-transaction bytes returned by `POST /v3/swap`. Bytes (not
    /// string) so binary payloads round-trip without re-encoding. For
    /// object-shaped payloads (TRON, TON) callers JSON-encode on the
    /// initiator and decode on the peer.
    let txPayload: Data

    /// Deposit address on the source chain. For PSBT this also lives encoded
    /// inside `txPayload`; for deposit-only chains (Cardano) this is the
    /// only routing info.
    let targetAddress: String

    /// THORChain-style inbound vault address. Optional — populated only for
    /// routes that go through TC-style inbound monitoring. Rare in SwapKit
    /// since we filter THORChain/Maya client-side; kept for forward
    /// compatibility.
    let inboundAddress: String?

    /// Optional memo. SwapKit V3 returned null for every chain observed in
    /// the Phase 0 spike; field exists for forward compatibility.
    let memo: String?

    /// Sub-provider tag for the verify screen ("CHAINFLIP", "NEAR",
    /// "GARDEN", "FLASHNET", "HARBOR"). Verbatim from `route.providers[0]`.
    let subProvider: String

    /// SwapKit swap identifier. Persisted for tracking + analytics. NOT
    /// accepted by `POST /track` — track by broadcast hash + chain id.
    let swapID: String

    /// Provider fee for this swap, raw in the base units of the coin the three
    /// fields below identify. A co-signer holds no quote, so a fee that does not
    /// travel here is one it can neither recover nor show.
    ///
    /// Read from the wire but not yet written by this app: iOS treats SwapKit's
    /// affiliate charge as embedded in the quoted rate (`SwapCryptoLogic`'s
    /// `affiliateFeeFiat` returns zero for SwapKit and the form shows an
    /// "included in rate" note instead of an amount), so there is no itemized
    /// initiator figure to carry. Populating one here would give the joiner a fee
    /// row and a total that the initiator's own verify screen does not show —
    /// the disagreement these fields exist to remove. A sender that does itemize
    /// it (Windows, Android, the SDK) reaches an iOS joiner through these fields.
    ///
    /// Display only: no signer reads any of them.
    var swapFee: String? = nil

    /// Coin context for `swapFee`. The amount alone is ambiguous — providers
    /// charge in the source gas coin, the sell asset or the destination token —
    /// and a 6-decimal fee read as an 18-decimal one is wrong by 10^12. All nil
    /// means "unknown"; the consumer renders no row rather than guessing a coin.
    var swapFeeChain: String? = nil
    var swapFeeTokenId: String? = nil
    var swapFeeDecimals: Int? = nil
}
