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
    }
    
    var check: some View {
        Image(systemName: "checkmark")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertSuccess)
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSuccess)
            .cornerRadius(20)
            .opacity(isChecked ? 1 : 0)
            .overlay(
                Circle()
                    .stroke(isChecked ? Theme.colors.alertSuccess : Theme.colors.border, lineWidth: 1)
            )
    }
    
    @ViewBuilder
    var description: some View {
        if let text {
            Text(NSLocalizedString(text, comment: "Checkbox description"))
                .font(font)
                .foregroundColor(Theme.colors.textLight)
                .multilineTextAlignment(alignment)
        }
    }
}

#Preview {
    VStack {
        Checkbox(isChecked: .constant(true), text: "sendingRightAddressCheck")
        Checkbox(isChecked: .constant(false), text: "sendingRightAddressCheck")
    }
}
