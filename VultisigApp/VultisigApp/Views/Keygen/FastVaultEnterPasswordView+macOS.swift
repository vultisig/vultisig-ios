//
//  FastVaultEnterPasswordView+macOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.09.2024.
//

import SwiftUI

extension FastVaultEnterPasswordView {

#if os(macOS)
    var body: some View {
        ZStack {
            Background()
            VStack {
                headerMac
                view
                    .padding(.horizontal, 25)
            }
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "password")
    }
#endif
}
