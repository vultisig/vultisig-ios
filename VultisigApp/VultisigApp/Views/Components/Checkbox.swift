//
//  Checkbox.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

struct Checkbox: View {
    @Binding var isChecked: Bool
    let text: String?
    var font: Font
    var alignment: TextAlignment
    var isExtended: Bool
    
    init(
        isChecked: Binding<Bool>,
        text: String? = nil,
        font: Font = Theme.fonts.bodySMedium,
        alignment: TextAlignment = .leading,
        isExtended: Bool = true
    ) {
        self._isChecked = isChecked
        self.text = text
        self.font = font
        self.alignment = alignment
        self.isExtended = isExtended
    }
    
    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 10) {
                check
                description
                
                if isExtended {
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: isChecked)
        .buttonStyle(.plain)
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(Theme.fonts.caption12)
            .foregroundColor(color)
            .frame(width: 24, height: 24)
            .background(bgColor)
            .cornerRadius(20)
            .opacity(isChecked ? 1 : 0)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 1)
            )
    }
    
    var color: Color {
        isChecked ? Theme.colors.alertSuccess : Theme.colors.border
    }
    
    var bgColor: Color {
        isChecked ? Theme.colors.bgSuccess : Theme.colors.bgSurface1
    }
    
    @ViewBuilder
    var description: some View {
        if let text {
            Text(NSLocalizedString(text, comment: "Checkbox description"))
                .font(font)
                .foregroundColor(Theme.colors.textSecondary)
                .multilineTextAlignment(alignment)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Checkbox(isChecked: .constant(true), text: "sendingRightAddressCheck")
        Checkbox(isChecked: .constant(false), text: "sendingRightAddressCheck")
    }
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
