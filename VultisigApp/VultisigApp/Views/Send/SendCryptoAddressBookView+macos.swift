//
//  SendCryptoAddressBookView+macos.swift
//  VultisigApp
//
//  Created by Johnny Luo on 21/7/2025.
//

#if os(macOS)
import SwiftUI
extension SendCryptoAddressBookView {
    var content: some View {
        VStack(spacing: 12) {
            listSelector
            list
        }
        .padding(16)
        .crossPlatformToolbar("addressBook".localized)
        .frame(width: 500)
    }
}

#endif
