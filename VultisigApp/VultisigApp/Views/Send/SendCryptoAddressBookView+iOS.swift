//
//  SendCryptoAddressBookView+iOS.swift
//  VultisigApp
//
//  Created by Johnny Luo on 21/7/2025.
//
#if os(iOS)
import SwiftUI
extension SendCryptoAddressBookView {
    var content: some View {
        VStack(spacing: 12) {
            title
            listSelector
            list
        }
        .padding(16)
    }
}
#endif
