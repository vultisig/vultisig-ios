//
//  KeysignStartInput.swift
//  VultisigApp
//
//  Two-mode input for `KeysignView`/`KeysignViewModel`. A plain (non-Hashable)
//  value built at the screen/router layer — it can carry a live `Vault`, so it
//  must NOT ride a `NavigationPath` route (routes carry the route-safe
//  `SigningKeysignRoute` and the router builds this at the screen boundary).
//
//    - `.ready`  — committee already known (paired path, or a joining
//                  cosigner): drive the ceremony directly.
//    - `.fast`   — fast vault: the committee only materialises once
//                  Vultiserver joins the relay session, so the view-model runs
//                  `FastVaultKeysignBootstrap` first (rendered as the
//                  "connecting" animation) and then drives the same ceremony.
//

import Foundation

enum KeysignStartInput {
    /// Paired / joining: the `KeysignInput` is fully formed (committee known).
    case ready(KeysignInput)
    /// Fast vault: run the relay-session bootstrap before signing.
    case fast(
        vault: Vault,
        keysignPayload: KeysignPayload?,
        customMessagePayload: CustomMessagePayload?,
        fastVaultPassword: String
    )
}

/// Display-only decode hints threaded from a joining cosigner's QR into the
/// keysign done screens (function name, token amount, etc.). Orthogonal to the
/// signing input, so it's kept out of `KeysignInput`; empty for every flow that
/// doesn't decode dApp/function metadata.
struct KeysignDecodedMetadata {
    var functionName: String?
    var tokenAmount: String?
    var tokenTicker: String?
    var tokenLogo: String?
    var tokenDisplay: String?
    var tokenIsUnlimited: Bool = false
    var functionSignature: String?
    var functionArguments: String?

    static let empty = KeysignDecodedMetadata()
}
