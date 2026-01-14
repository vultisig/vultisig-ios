//
//  TronFreezeView+macOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(macOS)
extension TronFreezeView {
    var main: some View {
        content
            .background(Theme.colors.bgPrimary)
            .task {
                await loadData()
            }
    }
}
#endif
