//
//  NewWalletNameView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension NewWalletNameView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
                .padding(.horizontal, 24)
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "")
    }
}
#endif
