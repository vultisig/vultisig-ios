import Foundation
import SwiftUI

struct TransactionMemoSelectorDropdown: View {
    
    @Binding var items: [TransactionMemoType]
    @Binding var selected: TransactionMemoType
    
    @Binding var coin: Coin
    
    var onSelect: ((TransactionMemoType) -> Void)?
    
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
            Text(selected.display(coin: coin))
            Spacer()
            
            Image(systemName: "chevron.down")
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
    
    private func getCell(for item: TransactionMemoType) -> some View {
        HStack(spacing: 12) {
            Text(item.display(coin: coin))
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
    
    private func handleSelection(for item: TransactionMemoType) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}
