//
//  SetupQRCodeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SetupQRCodeView {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .crossPlatformToolbar("chooseSetUp".localized)
    }
}
#endif
