//
//  SignSui.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// A pre-built Sui Programmable Transaction Block supplied by a dApp via the
/// Sui Wallet Standard. `unsignedTxMsg` is the base64-encoded `TransactionData`
/// BCS bytes: the coins, gas budget and recipients are already baked in, so the
/// signing pipeline forwards them verbatim to WalletCore's `signDirectMessage`
/// instead of reconstructing a `Pay` / `PaySui` input.
struct SignSui: Codable, Hashable {
    let unsignedTxMsg: String

    init(unsignedTxMsg: String) {
        self.unsignedTxMsg = unsignedTxMsg
    }

    init(proto: VSSignSui) {
        self.unsignedTxMsg = proto.unsignedTxMsg
    }

    func mapToProtobuff() -> VSSignSui {
        .with {
            $0.unsignedTxMsg = unsignedTxMsg
        }
    }
}
