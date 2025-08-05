//
//  Checkbox.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

struct Checkbox: View {
    @Binding var isChecked: Bool
    let text: String
    var font: Font = Theme.fonts.bodySMedium
    var alignment: TextAlignment = .leading
    var isExtended: Bool = true
    
    var body: some View {
        HStack(spacing: 10) {
            check
            description
            
            if isExtended {
                Spacer()
            }
        }
        .sensoryFeedback(.selection, trigger: isChecked)
        .onTapGesture {
            isChecked.toggle()
        }
    }
    
    var check: some View {
        Image(systemName: isChecked ? "checkmark" : "")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertInfo)
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSuccess)
            .cornerRadius(20)
            .overlay(
                Circle()
                    .stroke(isChecked ? Theme.colors.alertInfo : Theme.colors.border, lineWidth: 1)
            )
    }
    
    var description: some View {
        Text(NSLocalizedString(text, comment: "Checkbox description"))
            .font(font)
            .foregroundColor(Theme.colors.textLight)
            .multilineTextAlignment(alignment)
    }
}

#Preview {
    VStack {
        Checkbox(isChecked: .constant(true), text: "sendingRightAddressCheck")
        Checkbox(isChecked: .constant(false), text: "sendingRightAddressCheck")
    }
}
