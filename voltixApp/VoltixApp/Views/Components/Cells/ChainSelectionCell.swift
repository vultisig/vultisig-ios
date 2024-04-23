//
//  ChainSelectionCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

//struct ChainSelectionCell: View {
//    let assets: [Coin]
//    @Binding var showAlert: Bool
//    
//    @State var isSelected = false
//    @State var asset: Coin? = nil
//    
//    @EnvironmentObject var tokenSelectionViewModel: TokenSelectionViewModel
//    
//    var body: some View {
//        HStack(spacing: 16) {
//            image
//            text
//            Spacer()
//            toggleContent
//        }
//        .frame(height: 72)
//        .padding(.horizontal, 16)
//        .background(Color.blue600)
//        .cornerRadius(10)
//        .redacted(reason: asset==nil ? .placeholder : [])
//        .onAppear {
//            setData()
//        }
//    }
//    
//    var image: some View {
//        Image(asset?.logo ?? "Logo")
//            .resizable()
//            .frame(width: 32, height: 32)
//            .cornerRadius(100)
//    }
//    
//    var text: some View {
//        VStack(alignment: .leading, spacing: 6) {
//            Text(asset?.ticker ?? "Ticker")
//                .font(.body16MontserratBold)
//                .foregroundColor(.neutral0)
//            
//            Text(asset?.chain.name ?? "Name")
//                .font(.body12MontserratSemiBold)
//                .foregroundColor(.neutral0)
//        }
//    }
//    
//    var toggleContent: some View {
//        ZStack {
//            if assets.count>1, isSelected {
//                disabledToggle
//            } else {
//                enabledToggle
//            }
//        }
//    }
//    
//    var enabledToggle: some View {
//        toggle
//    }
//    
//    var disabledToggle: some View {
//        Button {
//            showAlert = true
//        } label: {
//            toggle
//                .disabled(true)
//        }
//    }
//    
//    var toggle: some View {
//        Toggle("Is selected", isOn: $isSelected)
//            .labelsHidden()
//            .scaleEffect(0.6)
//    }
//    
//    private func setData() {
//        asset = assets.first ?? Coin.example
//        
//        guard let asset else {
//            return
//        }
//        
//        if tokenSelectionViewModel.selection.contains(asset) {
//            isSelected = true
//        } else {
//            isSelected = false
//        }
//    }
//    
//    private func handleSelection(_ isSelected: Bool) {
//        guard let asset else {
//            return
//        }
//        
//        tokenSelectionViewModel.handleSelection(isSelected: isSelected, asset: asset)
//    }
//}

import SwiftUI

struct ChainSelectionCell: View {
    let assets: [Coin]
    @Binding var showAlert: Bool
    
    @State var isSelected = false
    @EnvironmentObject var tokenSelectionViewModel: TokenSelectionViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .onChange(of: tokenSelectionViewModel.selection) { oldValue, newValue in
                setData()
            }
    }
    
    var content: some View {
        ZStack {
            if assets.count>1, isSelected {
                disabledContent
            } else {
                enabledContent
            }
        }
    }
    
    var enabledContent: some View {
        cell
    }
    
    var disabledContent: some View {
        Button {
            showAlert = true
        } label: {
            cell
                .disabled(true)
        }
    }
    
    var cell: some View {
        let nativeAsset = assets.first
        
        return TokenSelectionCell(asset: nativeAsset ?? Coin.example)
            .redacted(reason: nativeAsset==nil ? .placeholder : [])
    }
    
    private func setData() {
        guard let nativeAsset = assets.first else {
            return
        }
        
        if tokenSelectionViewModel.selection.contains(nativeAsset) {
            isSelected = true
        } else {
            isSelected = false
        }
    }
}

#Preview {
    ZStack {
        Background()
        ChainSelectionCell(assets: [], showAlert: .constant(false))
    }
    .environmentObject(TokenSelectionViewModel())
}
