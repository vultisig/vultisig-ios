//
//  HiddenTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-16.
//

import SwiftUI

struct HiddenTextField: View {
    let placeholder: String
    @Binding var password: String
    
    @State private var isPasswordVisible: Bool = false
    
    var body: some View {
        field
    }
    
    var field: some View {
        HStack {
            textfield
            button
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(12)
    }
    
    var textfield: some View {
        ZStack(alignment: .leading) {
            if password.isEmpty {
                HStack {
                    Text(NSLocalizedString(placeholder, comment: ""))
                        .foregroundColor(Color.neutral500)
                        .font(.body12Menlo)
                    Spacer()
                }
            }
            
            if isPasswordVisible {
                 TextField(NSLocalizedString("", comment: ""), text: $password)
                    .borderlessTextFieldStyle()
            } else {
                SecureField(NSLocalizedString("", comment: ""), text: $password)
                    .borderlessTextFieldStyle()
            }
        }
        .submitLabel(.done)
        .colorScheme(.dark)
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
    }
    
    var button: some View {
        Button(action: {
            withAnimation {
                isPasswordVisible.toggle()
            }
        }) {
            Image(systemName: isPasswordVisible ? "eye": "eye.slash")
                .foregroundColor(.neutral0)
        }
        .contentTransition(.symbolEffect(.replace))
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            HiddenTextField(placeholder: "verifyPassword", password: .constant("password"))
            HiddenTextField(placeholder: "verifyPassword", password: .constant(""))
        }
    }
}
