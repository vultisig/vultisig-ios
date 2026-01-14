//
//  TronUnfreezeView+macOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(macOS)
extension TronUnfreezeView {
    var main: some View {
        content
            .background(Theme.colors.bgPrimary)
    }
}
#endif
