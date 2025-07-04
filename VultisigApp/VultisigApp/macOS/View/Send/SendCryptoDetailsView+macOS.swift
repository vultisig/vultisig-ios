//
//  SendCryptoDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(macOS)
import SwiftUI

extension SendCryptoDetailsView {
    var container: some View {
        content
    }
    
    var view: some View {
        VStack {
            tabs
            buttonContainer
                .padding(.horizontal, 8)
                .padding(.vertical, -12)
        }
    }
    
    var buttonContainer: some View {
        button
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
    }
    
    func setData() {
        Task {
            await getBalance()
        }
    }
}
#endif
