//
//  TronUnfreezeView+iOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(iOS)
extension TronUnfreezeView {
    var main: some View {
        content
            .background(Theme.colors.bgPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
    }
}
#endif
