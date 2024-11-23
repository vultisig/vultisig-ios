//
//  CoinDetailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension CoinDetailView {
    var content: some View {
        ZStack {
            Background()
            main
            
            if isLoading {
                loader
            }
        }
        .navigationTitle(NSLocalizedString(coin.ticker, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationRefreshButton() {
                    Task {
                        await refreshData()
                    }
                }
            }
        }
    }
    
    var main: some View {
        view
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
            .padding(.vertical, 30)
        }
    }
}
#endif
