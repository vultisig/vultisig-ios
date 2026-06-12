//
//  SwapModeTabs.swift
//  VultisigApp
//
//  Market / Limit tab row above the swap component. Market is active (underline);
//  Limit is visible but its order-execution is out of scope. State lives in the
//  details view model.
//

import SwiftUI

struct SwapModeTabs: View {
    @Binding var selected: SwapMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SwapMode.allCases) { mode in
                tab(for: mode)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func tab(for mode: SwapMode) -> some View {
        let isSelected = selected == mode
        return VStack(spacing: 6) {
            Text(mode.title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textTertiary)

            Rectangle()
                .frame(height: 1.5)
                .foregroundStyle(isSelected ? Theme.colors.primaryAccent4 : Color.clear)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selected = mode
            }
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var selected: SwapMode = .market
        var body: some View {
            SwapModeTabs(selected: $selected)
                .padding()
                .background(Theme.colors.bgPrimary)
        }
    }
    return PreviewContainer()
}
