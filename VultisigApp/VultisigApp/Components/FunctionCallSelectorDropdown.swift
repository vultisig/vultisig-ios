import Foundation
import SwiftUI

struct FunctionCallSelectorDropdown: View {

    @Binding var items: [FunctionCallType]
    @Binding var selected: FunctionCallType

    @Binding var coin: Coin

    var onSelect: ((FunctionCallType) -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedCell

            if isExpanded {
                cells
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
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
            Text(selected.display())
            Spacer()

            Image(systemName: "chevron.down")
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

    private func getCell(for item: FunctionCallType) -> some View {
        HStack(spacing: 12) {
            Text(item.display())
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

    private func handleSelection(for item: FunctionCallType) {
        isExpanded = false
        selected = item
        onSelect?(item)
    }
}
