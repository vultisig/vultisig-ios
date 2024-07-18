//
//  DefaultChainCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI

struct ToggleSelectionCell: View {
    let asset: CoinMeta?
    let assets: [CoinMeta]
    
    @State var isSelected = false
    
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            image
            text
            Spacer()
            toggle
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .onAppear {
            setData()
        }
        .onChange(of: assets.count, { oldValue, newValue in
            setData()
        })
        .onTapGesture {
            handleSelection()
        }
    }
    
    var image: some View {
        Image(asset?.logo ?? "")
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(32)
    }

    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset?.ticker ?? "")
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            
            Text(asset?.chain.name ?? "")
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
        }
    }
    
    var toggle: some View {
        Toggle("Is selected", isOn: $isSelected)
            .labelsHidden()
            .scaleEffect(0.6)
#if os(macOS)
            .scaleEffect(2)
            .offset(x: -12)
#endif
    }
    
    private func setData() {
        guard let asset else {
            return
        }
        
        isSelected = assets.contains(asset)
    }
    
    private func handleSelection() {
        guard let asset else {
            return
        }
        
        if assets.contains(asset) {
            removeAsset()
        } else {
            addAsset()
        }
    }
    
    private func addAsset() {
        guard let asset else {
            return
        }
        
        settingsDefaultChainViewModel.addChain(asset)
    }
    
    private func removeAsset() {
        guard let asset else {
            return
        }
        
        settingsDefaultChainViewModel.removeChain(asset)
    }
}

#Preview {
    ToggleSelectionCell(asset: CoinMeta.example, assets: [CoinMeta.example])
        .environmentObject(SettingsDefaultChainViewModel())
}
