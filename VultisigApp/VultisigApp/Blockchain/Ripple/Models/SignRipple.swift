//
//  SignRipple.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// A pre-built XRPL transaction supplied by a dApp (via the GemWallet API and
/// relayed by the browser extension). `rawJson` is the full XRPL transaction
/// JSON — an `OfferCreate`, cross-currency `Payment`, `OfferCancel` or
/// `TrustSet` — with its account, amounts and destination already baked in, so
/// the signing pipeline forwards it verbatim to WalletCore's Ripple `rawJson`
/// path instead of reconstructing an `opPayment` from `toAddress` / `toAmount`.
/// Every signer rebuilds its signing input from this same JSON, so each party
/// signs identical bytes.
struct SignRipple: Codable, Hashable {
    let rawJson: String

    init(rawJson: String) {
        self.rawJson = rawJson
    }

    init(proto: VSSignRipple) {
        self.rawJson = proto.rawJson
    }

    func mapToProtobuff() -> VSSignRipple {
        .with {
            $0.rawJson = rawJson
        }
    }
}
