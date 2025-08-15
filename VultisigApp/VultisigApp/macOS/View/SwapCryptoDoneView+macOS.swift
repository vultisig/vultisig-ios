//
//  SwapCryptoDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-08.
//

#if os(macOS)
import SwiftUI

extension SwapCryptoDoneView {
    var buttons: some View {
        HStack(spacing: 8) {
            trackButton
            doneButton
        }
        .padding(.vertical)
        .padding(.horizontal, 18)
        .background(Theme.colors.bgPrimary)
    }
}
#endif
