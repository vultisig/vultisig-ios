//
//  SendCryptoSecondaryDoneView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-09.
//

#if os(macOS)
import SwiftUI

extension SendCryptoSecondaryDoneView {
    var container: some View {
        ZStack {
            Background()
            
            VStack {
                headerMac
                content
            }
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "transactionDetails")
    }
}
#endif
