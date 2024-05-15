//
//  SelectorDropdown.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct SelectorDropdown: View {

    @Binding var items: [String]
    @Binding var selected: String

    var onSelect: ((Any) -> Void)?

    @State var isExpanded = false

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
            Text("\(selected)")
            Spacer()
            
            Text(selected.description)

            if isActive {
                Image(systemName: "chevron.down")
            }
        }
        .redacted(reason: selected.isEmpty ? .placeholder : [])
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
    }
        
    var cells: some View {
        ForEach(items, id: \.self) { item in
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
    
    private func getCell(for item: String) -> some View {
        HStack(spacing: 12) {
            Text(item)
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

    private func handleSelection(for item: String) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}

#Preview {
    SelectorDropdown(items: .constant([]), selected: .constant(.empty))
}
