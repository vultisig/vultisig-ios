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
}
