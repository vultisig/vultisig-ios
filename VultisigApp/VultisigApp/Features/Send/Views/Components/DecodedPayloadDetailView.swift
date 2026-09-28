//
//  DecodedPayloadDetailView.swift
//  VultisigApp
//
//  The decoded dApp-signing payload's detail view, shared by every review
//  surface that shows one. Exactly one of the seven `sign*` payload kinds is
//  ever present on a `KeysignPayload`, so at most one branch renders.
//

import SwiftUI

struct DecodedPayloadDetailView: View {
    let payload: KeysignPayload?
    let vault: Vault?

    /// Whether a branch below would render, so callers that place their own
    /// chrome (a separator, for example) around this view only when it has
    /// something to show can ask without duplicating the branch logic.
    var hasContent: Bool {
        payload?.signDirect != nil
            || payload?.signAmino != nil
            || payload?.signSolana != nil
            || (payload?.signTon != nil && payload?.coin != nil && vault != nil)
            || payload?.signBitcoin != nil
            || payload?.signSui != nil
            || payload?.signRipple != nil
    }

    var body: some View {
        if let signDirect = payload?.signDirect {
            SignDirectDisplayView(signDirect: signDirect)
        } else if let signAmino = payload?.signAmino {
            SignAminoDisplayView(signAmino: signAmino)
        } else if let signSolana = payload?.signSolana {
            SignSolanaDisplayView(signSolana: signSolana)
        } else if let signTon = payload?.signTon,
                  let coin = payload?.coin,
                  let vault {
            SignTonDisplayView(
                signTon: signTon,
                keysignPayload: payload,
                vault: vault,
                fromAddress: coin.address
            )
        } else if let signBitcoin = payload?.signBitcoin {
            SignBitcoinDisplayView(signBitcoin: signBitcoin)
        } else if let signSui = payload?.signSui {
            SignSuiDisplayView(signSui: signSui)
        } else if let signRipple = payload?.signRipple {
            SignRippleDisplayView(signRipple: signRipple)
        }
    }
}
