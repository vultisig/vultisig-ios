import Foundation
import SwiftUI

struct GenericSelectorDropDown<T: Identifiable & Equatable>: View {
    
    @Binding var items: [T]
    @Binding var selected: T
    var mandatoryMessage: String?
    var descriptionProvider: (T) -> String
    var onSelect: ((T) -> Void)?
    
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
            Text(descriptionProvider(selected))
            
            if !items.contains(selected) {
                Text(mandatoryMessage ?? "")
                    .font(.body14MontserratMedium)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            if isActive {
                Image(systemName: "chevron.down")
            }
        }
        .redacted(reason: descriptionProvider(selected).isEmpty ? .placeholder : [])
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
            Text(descriptionProvider(item))
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
    
    private func handleSelection(for item: T) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}
