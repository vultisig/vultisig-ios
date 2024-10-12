//
//  FastVaultEnterPasswordView+macOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.09.2024.
//

#if os(macOS)
import SwiftUI

extension FastVaultEnterPasswordView {
    var body: some View {
        ZStack {
            Background()
            VStack {
                headerMac
                view
                    .padding(.horizontal, 25)
            }
            if isLoading {
                Loader()
            }
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "password")
    }
}
#endif
