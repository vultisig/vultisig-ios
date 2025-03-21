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
    var font: Font = .body14MontserratMedium
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
        .onTapGesture {
            isChecked.toggle()
        }
    }
    
    var check: some View {
        Image(systemName: isChecked ? "checkmark" : "")
            .font(.body14MenloBold)
            .foregroundColor(.neutral0)
            .frame(width: 24, height: 24)
            .background(isChecked ? Color.turquoise600 : Color.blue200)
            .cornerRadius(20)
    }
    
    var description: some View {
        Text(NSLocalizedString(text, comment: "Checkbox description"))
            .font(font)
            .foregroundColor(.neutral200)
            .multilineTextAlignment(alignment)
    }
}

#Preview {
    VStack {
        Checkbox(isChecked: .constant(true), text: "sendingRightAddressCheck")
        Checkbox(isChecked: .constant(false), text: "sendingRightAddressCheck")
    }
}
