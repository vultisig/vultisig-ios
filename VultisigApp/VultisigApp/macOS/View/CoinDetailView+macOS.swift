//
//  CoinDetailView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension CoinDetailView {
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
        .onChange(of: isSendLinkActive) { oldValue, newValue in
            if isSendLinkActive {
                resetActive = false
            } else {
                resetActive = true
            }
        }
    }
    
    var headerMac: some View {
        CoinDetailHeader(title: coin.ticker, refreshData: refreshData)
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actionButtons
                cells
            }
            .padding(.horizontal, 16)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
}
#endif
