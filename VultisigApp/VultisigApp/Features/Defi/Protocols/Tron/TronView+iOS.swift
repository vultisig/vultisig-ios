//
//  TronView+iOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(iOS)
extension TronView {
    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
