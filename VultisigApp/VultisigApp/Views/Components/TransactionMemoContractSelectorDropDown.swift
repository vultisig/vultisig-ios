//
//  TransactionMemoContractSelectorDropDown.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import Foundation
import SwiftUI

struct TransactionMemoContractSelectorDropDown: View {
    
    @Binding var items: [TransactionMemoContractType]
    @Binding var selected: TransactionMemoContractType
    
    var onSelect: ((TransactionMemoContractType) -> Void)?
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedCell
            
            if isActive && isExpanded {
                cells
            }
        }
        .padding(.horizontal, 12)
        .background(Color.blue600)
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
            Text("\(selected.rawValue)")
            Spacer()
            
            if isActive {
                Image(systemName: "chevron.down")
            }
        }
        .redacted(reason: selected.rawValue.isEmpty ? .placeholder : [])
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
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
    
    private func getCell(for item: TransactionMemoContractType) -> some View {
        HStack(spacing: 12) {
            Text(item.rawValue)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
            Spacer()
            
            if selected == item {
                Image(systemName: "checkmark")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }
        }
        .frame(height: 48)
    }
    
    var isActive: Bool {
        return items.count > 1
    }
    
    private func handleSelection(for item: TransactionMemoContractType) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}
