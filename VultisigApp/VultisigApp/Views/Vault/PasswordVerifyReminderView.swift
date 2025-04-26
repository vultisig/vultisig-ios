//
//  PasswordVerifyReminderView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-25.
//

import SwiftUI

struct PasswordVerifyReminderView: View {
    let vault: Vault
    @Binding var isSheetPresented: Bool
    
    @State var isLoading = false
    @State var verifyPassword = ""
    @State var isPasswordVisible = false
    
    private let fastVaultService: FastVaultService = .shared
    
    var body: some View {
        ZStack {
            Background()
            view
            
            if isLoading {
                loader
            }
        }
    }
    
    var loader: some View {
        ZStack {
            overlay
            
            ProgressView()
                .preferredColorScheme(.dark)
        }
    }
    
    var overlay: some View {
        Color.black
            .ignoresSafeArea()
            .opacity(0.3)
    }

    var view: some View {
        VStack(spacing: 16) {
            header
            textField
            verifyButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .blur(radius: isLoading ? 1 : 0)
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
            Task {
                isLoading = true
                await verifyPasswordIsValid()
            }
        } label: {
            FilledButton(title: "verify")
        }
        .buttonStyle(.plain)
    }
    
    private func verifyPasswordIsValid() async {
        let isValid = await fastVaultService.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: verifyPassword
        )
        
        if isValid {
            print("Correct")
        } else {
            print("Incorrect")
        }
        
        isLoading = false
    }
}
