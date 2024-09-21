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
            main
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "setup")
            .padding(.bottom, 8)
    }
    
    var pairButton: some View {
        Button(action: {
            showSheet = true
        }) {
            OutlineButton(title: "pair")
        }
    }
}
#endif
