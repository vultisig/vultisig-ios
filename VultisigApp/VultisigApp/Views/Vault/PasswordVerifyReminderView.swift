//
//  PasswordVerifyReminderView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-25.
//

import SwiftUI

struct PasswordVerifyReminderView: View {
    @Binding var isSheetPresented: Bool
    
    @State var verifyPassword = ""
    @State var isPasswordVisible = false
    
    var body: some View {
        ZStack {
            Background()
            view
        }
    }

    var view: some View {
        VStack(spacing: 16) {
            header
            textField
            verifyButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    var header: some View {
        HStack {
            closeButton
                .disabled(true)
                .opacity(0)

            Spacer()

            title

            Spacer()

            closeButton
        }
        .foregroundColor(.neutral0)
        .font(.body16BrockmannMedium)
    }
    
    var textField: some View {
        HStack {
            if isPasswordVisible {
                TextField(NSLocalizedString("verifyPassword", comment: "").capitalized, text: $verifyPassword)
                    .borderlessTextFieldStyle()
            } else {
                SecureField(NSLocalizedString("verifyPassword", comment: "").capitalized, text: $verifyPassword)
                    .borderlessTextFieldStyle()
            }
            
            hideButton
        }
        .foregroundColor(.neutral0)
        .font(.body14BrockmannMedium)
        .borderlessTextFieldStyle()
        .keyboardType(.default)
        .textInputAutocapitalization(.never)
        .textContentType(.password)
        .frame(height: 56)
        .padding(.horizontal, 24)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.turquoise600, lineWidth: 1)
        )
        .padding(.top, 12)
    }
    
    var hideButton: some View {
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
    
    var title: some View {
        Text(NSLocalizedString("biweeklyPasswordVerifyTitle", comment: ""))
            .multilineTextAlignment(.center)
    }
    
    var closeButton: some View {
        Button {
            isSheetPresented = false
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
    }

    var verifyButton: some View {
        Button {
            
        } label: {
            FilledButton(title: "verify")
        }
        .buttonStyle(.plain)
    }
}
