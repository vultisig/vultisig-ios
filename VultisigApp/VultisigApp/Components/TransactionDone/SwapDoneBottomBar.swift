//
//  SwapDoneBottomBar.swift
//  VultisigApp
//
//  Bottom bar of the swap done screen, shared by the initiator and the
//  co-signer. A failed swap the vault can place again gets a full-width
//  Try again above Track / Done, and Done steps down to secondary so the
//  bar keeps a single primary action.
//

import SwiftUI

struct SwapDoneBottomBar: View {
    /// Invoked by Try again; `nil` hides it.
    let onTryAgain: (() -> Void)?
    /// Invoked by Track; `nil` hides it.
    let onTrack: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let onTryAgain {
                PrimaryButton(title: "tryAgain", action: onTryAgain)
            }
            HStack(spacing: 8) {
                if let onTrack {
                    PrimaryButton(title: "track", type: .secondary, action: onTrack)
                }
                PrimaryButton(title: "done", type: onTryAgain == nil ? .primary : .secondary, action: onDone)
            }
        }
    }
}
