//
//  ServerBackupVerificationView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-13.
//

import SwiftUI
import SwiftData
import RiveRuntime

struct ServerBackupVerificationView: View {
    let vault: Vault
    let selectedTab: SetupVaultState?
    let email: String

    @ObservedObject var viewModel: KeygenViewModel

    @FocusState private var focusedField: Int?

    @State var otp: [String] = Array(repeating: "", count: 5)

    @State var isLoading: Bool = false
    @State var isNavigationActive: Bool = false
    
    @State var alertDescription = "verificationCodeTryAgain"
    @State var showAlert: Bool = false
    @State var showHomeView: Bool = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    var verificationCode: String {
        return otp.joined().trimmingCharacters(in: .whitespaces)
    }

    let animationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    
    var body: some View {
        ZStack {
            Background()
            container
        }
        .onAppear {
            focusedField = 0
        }
        .safeAreaInset(edge: .bottom) {
            cancelButton
        }
        .animation(.easeInOut, value: showAlert)
        .navigationDestination(isPresented: $isNavigationActive) {
            if showHomeView {
                HomeView()
            } else {
                BackupVaultNowView(vault: vault)
            }
        }
        .onDisappear {
            animationVM.stop()
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("enter5DigitVerificationCode", comment: ""))
            .font(.body34BrockmannMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.leading)
            .padding(.top, 50)
    }
    
    var description: some View {
        Text(NSLocalizedString("enter5DigitVerificationCodeDescription", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var textField: some View {
        HStack(spacing: 8) {
            field
            pasteButton
        }
        .colorScheme(.dark)
        .padding(.top, 32)
    }
    
    var field: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                TextField("", text: $otp[index])
                    .foregroundColor(.neutral0)
                    .disableAutocorrection(true)
                    .borderlessTextFieldStyle()
                    .font(.body16BrockmannMedium)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 46, height: 46)
                    .background(Color.blue600)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(getBorderColor(index), lineWidth: 1)
                    )
                    .focused($focusedField, equals: index)
                    .onChange(of: otp[index]) { _, newValue in
                        handleInputChange(newValue, index: index)
                    }
            }
        }
    }

    private var cancelButton: some View {
        Button {
            deleteVault()
        } label: {
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("emailSentTo", comment: ""), email))
                    .font(.body14BrockmannMedium)
                    .foregroundColor(.extraLightGray)

                Text(NSLocalizedString("changeEmailAndRestart", comment: ""))
                    .font(.body14BrockmannMedium)
                    .foregroundColor(.lightText)
                    .underline()
            }
        }
        .padding(.bottom, 24)
    }

    private func handleInputChange(_ newValue: String, index: Int) {
        if newValue.count > 1 {
            otp[index] = String(newValue.last!)
        }

        if !newValue.isEmpty && index < 4 {
            focusedField = index + 1
        } else if newValue.isEmpty && index > 0 {
            focusedField = index - 1
        }

        if verificationCode.count == 5 {
            verifyCode()
        }
    }

    private func getBorderColor(_ index: Int) -> Color {
        if showAlert {
            return .alertRed
        } else {
            return focusedField == index ? .blue200 : .blue400
        }
    }

    var pasteButton: some View {
        Button {
            pasteCode()
        } label: {
            Text(NSLocalizedString("paste", comment: ""))
                .padding(12)
                .frame(height: 46)
                .font(.body16BrockmannMedium)
                .foregroundColor(.neutral0)
                .background(Color.blue600)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue200, lineWidth: 1)
                )
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
    }
    
    var loadingText: some View {
        HStack {
            animationVM.view()
                .frame(width: 24, height: 24)
            
            Text(NSLocalizedString("verifyingCodePleaseWait", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body14BrockmannMedium)
            
            Spacer()
        }
    }
    
    var alertText: some View {
        Text(NSLocalizedString(alertDescription, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.alertRed)
            .font(.body14BrockmannMedium)
    }
    
    private func verifyCode() {
        guard !verificationCode.isEmpty else {
            alertDescription = "emptyField"
            showAlert = true
            return
        }
        
        Task {
            alertDescription = "verificationCodeTryAgain"
            isLoading = true
            
            (isNavigationActive, showAlert) = await FastVaultService.shared.verifyBackupOTP(
                ecdsaKey: vault.pubKeyECDSA,
                OTPCode: verificationCode
            )
            
            isLoading = false
        }
    }
    
    private func deleteVault() {
        modelContext.delete(vault)
        isLoading = true
        
        do {
            try modelContext.save()
            isLoading = false
            showHomeView = true
            isNavigationActive = true
        } catch {
            print("Error: \(error)")
        }
    }
}

#Preview {
    ServerBackupVerificationView(vault: Vault.example, selectedTab: .secure, email: "mail@email.com", viewModel: KeygenViewModel())
}
