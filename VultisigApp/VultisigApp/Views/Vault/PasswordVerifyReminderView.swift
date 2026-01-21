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

    @AppStorage("biweeklyPasswordVerifyDate") var biweeklyPasswordVerifyDate: Double?
    
    @State var showError = false
    @State var errorText = ""
    
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
        .animation(.easeInOut, value: showError)
        .onDisappear {
            handleCloseTap()
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
        VStack(spacing: 12) {
            header
            separator
            description
            field
            Spacer(minLength: 0)
            verifyButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .blur(radius: isLoading ? 1 : 0)
    }
    
    var separator: some View {
        LinearSeparator()
            .opacity(0.8)
    }

    var header: some View {
        Text(NSLocalizedString("biweeklyPasswordVerifyTitle", comment: ""))
            .multilineTextAlignment(.center)
            .foregroundColor(Theme.colors.textSecondary)
            .font(Theme.fonts.bodySMedium)
    }
    
    var description: some View {
        Text(NSLocalizedString("biweeklyPasswordVerifyDescription", comment: ""))
            .multilineTextAlignment(.center)
            .foregroundColor(Theme.colors.textTertiary)
            .font(Theme.fonts.caption12)
            .padding(.horizontal, 28)
    }
    
    var field: some View {
        ZStack {
            textField
            
            if showError {
                errorContent
                    .offset(y: 48)
            }
        }
        .padding(.bottom)
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
        .colorScheme(.dark)
        .foregroundColor(Theme.colors.textPrimary)
        .font(Theme.fonts.bodySMedium)
        .borderlessTextFieldStyle()
        .frame(height: 56)
        .padding(.horizontal, 24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(showError ? Theme.colors.alertError : Color.clear, lineWidth: 1)
        )
    }
    
    var hideButton: some View {
        Button(
            action: {
                withAnimation {
                    isPasswordVisible.toggle()
                }
            },
            label: {
                Image(systemName: isPasswordVisible ? "eye": "eye.slash")
                    .foregroundColor(Theme.colors.textPrimary)
            }
        )
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }

    var verifyButton: some View {
        PrimaryButton(title: "verify") {
            handleButtonTap()
        }
    }
    
    var errorContent: some View {
        Text(NSLocalizedString(errorText, comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.alertError)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func verifyPasswordIsValid() async {
        guard !verifyPassword.isEmpty else {
            errorText = "emptyField"
            showError = true
            isLoading = false
            return
        }
        
        showError = false
        
        let isValid = await fastVaultService.get(
            pubKeyECDSA: vault.pubKeyECDSA,
            password: verifyPassword
        )
        
        if isValid {
            handleCloseTap()
        } else {
            errorText = "incorrectPassword"
            showError = true
        }
        
        isLoading = false
    }
    
    private func handleCloseTap() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        biweeklyPasswordVerifyDate = startOfToday.timeIntervalSince1970
        isSheetPresented = false
    }
    
    private func handleButtonTap() {
        Task {
            isLoading = true
            await verifyPasswordIsValid()
        }
    }
}
