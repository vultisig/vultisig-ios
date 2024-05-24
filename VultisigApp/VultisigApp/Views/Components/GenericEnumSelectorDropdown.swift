//
//  GenericEnumSelectorDropdown.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/05/24.
//

import Foundation
import SwiftUI

struct GenericEnumSelectorDropdown<T: Identifiable & CaseIterable & CustomStringConvertible>: View where T.AllCases: RandomAccessCollection {
    
    @Binding var items: [T]
    @Binding var selected: T
    
    var onSelect: ((T) -> Void)?
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedCell
            
            if isExpanded {
                cells
            }
        }
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
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
            Text(selected.description.toFormattedTitleCase())
            Spacer()
            
            Image(systemName: "chevron.down")
        }
        .redacted(reason: selected.description.isEmpty ? .placeholder : [])
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
    
    private func getCell(for item: T) -> some View {
        HStack(spacing: 12) {
            Text(item.description.toFormattedTitleCase())
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
            Spacer()
            
            if selected.id == item.id {
                Image(systemName: "checkmark")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }
        }
        .frame(height: 48)
    }
    
    private func handleSelection(for item: T) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}
