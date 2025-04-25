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

    @AppStorage("biweeklyPasswordVerifyDate") var monthlyReminderDate: Date = Date()
    
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
            Spacer()
            verifyButton
        }
        .onAppear {
            monthlyReminderDate = Date()
        }
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
        .padding(.top, 30)
        .foregroundColor(.neutral0)
        .font(.body16BrockmannMedium)
    }
    
    var textField: some View {
        HStack {
            SecureField(NSLocalizedString("verifyPassword", comment: "").capitalized, text: $verifyPassword)
                .foregroundColor(.neutral0)
                .borderlessTextFieldStyle()
                .keyboardType(.default)
                .textInputAutocapitalization(.never)
                .textContentType(.password)
            
            hideButton
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
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
        .padding(.horizontal, 16)
        .buttonStyle(.plain)
    }
}
