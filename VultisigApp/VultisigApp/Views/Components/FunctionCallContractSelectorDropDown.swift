//
//  FunctionCallContractSelectorDropDown.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//
import Foundation
import SwiftUI

struct FunctionCallContractSelectorDropDown: View {
    
    @Binding var items: [FunctionCallContractType]
    @Binding var selected: FunctionCallContractType
    var coin: Coin
    
    var onSelect: ((FunctionCallContractType) -> Void)?
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedCell
            
            if isActive && isExpanded {
                cells
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .disabled(!isActive)
    }
    
    var selectedCell: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            cell
        }
    }
    
    var cell: some View {
        HStack(spacing: 12) {
            Text(selected.getDescription(for: coin))
            Spacer()
            
            if isActive {
                Image(systemName: "chevron.down")
            }
        }
        .redacted(reason: selected.rawValue.isEmpty ? .placeholder : [])
        .font(Theme.fonts.bodyMRegular)
        .foregroundColor(Theme.colors.textPrimary)
        .frame(height: 48)
    }
    
    var cells: some View {
        ForEach(items, id: \.id) { item in
            Button {
                handleSelection(for: item)
            } label: {
                VStack(spacing: 0) {
                    Separator()
                    getCell(for: item)
                }
            }
        }
    }
    
    private func getCell(for item: FunctionCallContractType) -> some View {
        HStack(spacing: 12) {
            Text(item.getDescription(for: coin))
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
            
            Spacer()
            
            if selected == item {
                Image(systemName: "checkmark")
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundColor(Theme.colors.textPrimary)
            }
        }
        .frame(height: 48)
    }
    
    var isActive: Bool {
        return items.count > 1
    }
    
    private func handleSelection(for item: FunctionCallContractType) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}
