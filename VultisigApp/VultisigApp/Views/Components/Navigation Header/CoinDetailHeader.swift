//
//  CoinDetailHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-07.
//

import SwiftUI

struct CoinDetailHeader: View {
    let title: String
    let refreshData: () async -> Void
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(title)
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        NavigationRefreshButton() {
            Task {
                await refreshData()
            }
        }
    }
}

#Preview {
    func refreshData() async {}
    
    return CoinDetailHeader(title: "ETH", refreshData: refreshData)
}
