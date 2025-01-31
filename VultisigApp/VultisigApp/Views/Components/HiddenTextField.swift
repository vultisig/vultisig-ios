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
    var showHideOption: Bool = true
    
    @State var isPasswordVisible: Bool = false
    
    var body: some View {
        field
            .onAppear {
                setData()
            }
    }
    
    var field: some View {
        HStack {
            textfield
            
            if showHideOption {
                button
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
    }
    
    var textfield: some View {
        ZStack(alignment: .leading) {
            if password.isEmpty {
                HStack {
                    Text(NSLocalizedString(placeholder, comment: ""))
                        .foregroundColor(Color.neutral500)
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
        .font(.body16BrockmannMedium)
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
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }
    
    private func setData() {
        if !showHideOption {
            isPasswordVisible = true
        }
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
