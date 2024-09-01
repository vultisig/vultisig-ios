//
//  ImportWalletViewMac.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-01.
//

#if os(macOS)
import SwiftUI

extension ImportWalletView {
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
        }
    }
}
#endif
