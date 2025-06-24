//
//  SendDetailsAssetTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct SendDetailsAssetTab: View {
    @ObservedObject var tx: SendTransaction
    
    @State var isExpanded: Bool = true
    
    var body: some View {
        VStack(spacing: 16) {
            titleSection
            
            if isExpanded {
                separator
                assetSelectionSection
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .padding(1)
    }
    
    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("asset", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
            if isExpanded {
                Spacer()
            } else {
                // Selected asset
                Spacer()
                // Edit tools
            }
        }
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var assetSelectionSection: some View {
        VStack {
            chainSelection
        }
    }
    
    var chainSelection: some View {
        HStack(spacing: 8) {
            chainSelectionTitle
            selectedChainCell
            Spacer()
        }
    }
    
    var chainSelectionTitle: some View {
        Text(NSLocalizedString("from", comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var selectedChainCell: some View {
        SwapFromToChain(chain: tx.coin.chain)
    }
}

#Preview {
    SendDetailsAssetTab(tx: SendTransaction())
}
