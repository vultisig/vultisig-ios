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
                header
                content
            }
        }
    }
    
    var header: some VIew {
        GeneralMacHeader(title: "transactionDetails")
    }
}
#endif
