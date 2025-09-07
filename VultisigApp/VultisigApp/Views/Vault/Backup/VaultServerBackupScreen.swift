//
//  VaultServerBackupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/09/2025.
//

import SwiftUI

struct VaultServerBackupScreen: View {
    enum FocusedField {
        case email, password
    }
    
    let vault: Vault
    @StateObject var viewModel = VaultServerBackupViewModel()
    @Environment(\.dismiss) var dismiss
    
    @StateObject var keyboardObserver = KeyboardObserver()
    @State var scrollViewProxy: ScrollViewProxy?
    @State var showAlert = false
    @State var emailExpanded = true
    @State var passwordExpanded = false
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    private let passwordBottomId = "passwordBottomId"
    
    var body: some View {
        Screen(title: "serverBackup".localized) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        InfoBannerView(
                            description: (viewModel.alertError ?? ResendVaultShareError.unknown).localizedDescription,
                            type: .error,
                            leadingIcon: "triangle-alert"
                        )
                        .transition(.verticalGrowAndFade)
                        .showIf(showAlert)
                        
                        emailTextField
                        passwordTextField
                    }
                }
                .onLoad {
                    scrollViewProxy = proxy
                }
            }
        }
        .onSubmit {
            if focusedFieldBinding == .email {
                focusedFieldBinding = .password
            } else {
                focusedFieldBinding = nil
            }
        }
        .overlay(viewModel.isLoading ? Loader() : nil)
        .onLoad {
            focusedFieldBinding = .email
            viewModel.onLoad()
        }
        .onChange(of: viewModel.showAlert) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                showAlert = newValue
            }
        }
        .onChange(of: focusedFieldBinding) { oldValue, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
//        .onChange(of: focusedField) { oldValue, newValue in
//            if newValue == .password {
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                    withAnimation {
//                        scrollViewProxy?.scrollTo(passwordBottomId, anchor: .bottom)
//                    }
//                }
//            }
//        }
        .platformSheet(isPresented: $viewModel.showSuccess) {
            ServerVaultCheckInboxScreen(isPresented: $viewModel.showSuccess)
        }
    }
    
    var emailTextField: some View {
        FormExpandableSection(
            title: "email".localized,
            isValid: viewModel.validEmail,
            value: viewModel.email,
            showValue: true,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .email
        ) {
            focusedFieldBinding = $0 ? .email : .password
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text("enterYourEmail".localized)
                    .font(Theme.fonts.largeTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                
                CommonTextField(
                    text: $viewModel.email,
                    placeholder: "enterYourEmail".localized,
                    error: $viewModel.emailError
                )
                .focused($focusedField, equals: .email)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
#endif
            }
        }
    }
    
    var passwordTextField: some View {
        FormExpandableSection(
            title: "password".localized,
            isValid: viewModel.passwordError == nil,
            value: viewModel.password,
            showValue: false,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .password
        ) {
            focusedFieldBinding = $0 ? .password : .email
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text("vaultPassword".localized)
                    .font(Theme.fonts.largeTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("enterVaultPassword".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
                
                SecureTextField(
                    value: $viewModel.password,
                    placeholder: "enterYourPassword".localized,
                    error: $viewModel.passwordError
                )
                .focused($focusedField, equals: .password)
                
                Spacer()
                
                PrimaryButton(title: "next".localized) {
                    focusedFieldBinding = nil
                    Task {
                        await viewModel.requestServerVaultShare(vault: vault)
                    }
                }
                .disabled(!viewModel.validForm)
            }
            VStack {}
                .frame(height: 1)
                .id(passwordBottomId)
        }
    }
}
