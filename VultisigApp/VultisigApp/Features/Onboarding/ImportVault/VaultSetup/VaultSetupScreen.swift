//
//  VaultSetupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI

struct VaultSetupScreen: View {
    let tssType: TssType
    let keyImportInput: KeyImportInput?
    let setupType: KeyImportSetupType

    enum FocusedField {
        case name, referral, email, password, passwordConfirm, hint
    }

    @StateObject var viewModel: VaultSetupViewModel

    @State var scrollViewProxy: ScrollViewProxy?
    @State var focusedFieldBinding: FocusedField? = .none
    @FocusState private var focusedField: FocusedField?
    @State var hintExpanded = false
    @State var referralExpanded = false
    @Environment(\.router) var router

    init(tssType: TssType, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType? = nil) {
        self.tssType = tssType
        self.keyImportInput = keyImportInput
        self.setupType = setupType ?? .fast
        _viewModel = StateObject(wrappedValue: VaultSetupViewModel(setupType: setupType ?? .fast))
    }

    var body: some View {
        FormScreen(
            title: "vaultSetup".localized,
            fixedHeight: false,
            validForm: $viewModel.validForm,
            onContinue: onContinue
        ) {
            nameSection

            if viewModel.showFastSignFields {
                emailSection
                passwordSection
            }
        }
        .onLoad {
            focusedFieldBinding = .name
            viewModel.onLoad()
        }
        .onChange(of: focusedFieldBinding) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = newValue
            }
        }
        .onSubmit {
            onContinue()
        }
    }

    var nameSection: some View {
        FormExpandableSection(
            title: "name".localized,
            isValid: viewModel.nameField.valid,
            value: viewModel.nameField.value,
            showValue: true,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .name
        ) {
            focusedFieldBinding = $0 ? .name : .email
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("nameYourVault".localized)
                        .font(Theme.fonts.title1)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("newWalletNameDescription".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CommonTextField(
                    text: $viewModel.nameField.value,
                    placeholder: viewModel.nameField.placeholder,
                    error: $viewModel.nameField.error
                )
                .focused($focusedField, equals: .name)

                ExpandableView(isExpanded: $referralExpanded) {
                    expandableSecondaryFieldHeader(isExpanded: $referralExpanded, label: "addReferral".localized)
                } content: {
                    CommonTextField(
                        text: $viewModel.referralField.value,
                        placeholder: viewModel.referralField.placeholder ?? .empty,
                        error: $viewModel.referralField.error,
                    )
                    .focused($focusedField, equals: .referral)
                }
            }
        }
    }

    var emailSection: some View {
        FormExpandableSection(
            title: viewModel.emailField.label ?? .empty,
            isValid: viewModel.emailField.valid,
            value: viewModel.emailField.value,
            showValue: true,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: .email
        ) {
            focusedFieldBinding = $0 ? .email : .password
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text("enterYourEmail".localized)
                    .font(Theme.fonts.title1)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("enterVaultEmail".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)

                CommonTextField(
                    text: $viewModel.emailField.value,
                    placeholder: viewModel.emailField.placeholder ?? .empty,
                    error: $viewModel.emailField.error,
                )
                .focused($focusedField, equals: .email)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
#endif
            }
        }
    }

    var passwordSection: some View {
        FormExpandableSection(
            title: "password".localized,
            isValid: viewModel.passwordField.valid && viewModel.passwordConfirmField.valid,
            value: "",
            showValue: false,
            focusedField: $focusedFieldBinding,
            focusedFieldEquals: [.password, .passwordConfirm]
        ) {
            focusedFieldBinding = $0 ? .password : .email
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                InfoBannerView(
                    description: "PasswordCannotBeReset".localized,
                    type: .warning,
                    leadingIcon: "circle-info"
                )

                SecureTextField(
                    value: $viewModel.passwordField.value,
                    placeholder: viewModel.passwordField.placeholder,
                    error: $viewModel.passwordField.error
                )
                .focused($focusedField, equals: .password)

                SecureTextField(
                    value: $viewModel.passwordConfirmField.value,
                    placeholder: viewModel.passwordConfirmField.placeholder,
                    error: $viewModel.passwordConfirmField.error
                )
                .focused($focusedField, equals: .passwordConfirm)

                ExpandableView(isExpanded: $hintExpanded) {
                    expandableSecondaryFieldHeader(isExpanded: $hintExpanded, label: "addHint".localized)
                } content: {
                    CommonTextField(
                        text: $viewModel.hintField.value,
                        placeholder: viewModel.hintField.placeholder ?? .empty,
                        error: $viewModel.hintField.error,
                    )
                    .focused($focusedField, equals: .hint)
                }
            }
        }
    }

    func expandableSecondaryFieldHeader(isExpanded: Binding<Bool>, label: String) -> some View {
        Button {
            withAnimation(.interpolatingSpring) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.footnote)
                Spacer()
                Icon(named: "chevron-down-small", color: Theme.colors.textPrimary, size: 16)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
            }
            .padding(.bottom, isExpanded.wrappedValue ? 12 : 0)
        }
        .contentShape(Rectangle())
    }

    func onContinue() {
        if viewModel.showFastSignFields {
            switch focusedField {
            case .name, .referral:
                focusedFieldBinding = .email
            case .email:
                focusedFieldBinding = .password
            case .password:
                focusedFieldBinding = .passwordConfirm
            case .passwordConfirm, .hint:
                break
            case nil:
                break
            }
        }

        guard viewModel.validForm else { return }
        router.navigate(to: OnboardingRoute.keyImportNewVaultSetup(
            vault: viewModel.getVault(keyImportInput: keyImportInput),
            keyImportInput: keyImportInput,
            fastSignConfig: viewModel.showFastSignFields ? viewModel.fastConfig : nil,
            setupType: setupType
        ))
    }
}

#Preview {
    VaultSetupScreen(tssType: .KeyImport, keyImportInput: .init(mnemonic: "test", chainSettings: [ChainImportSetting(chain: .bitcoin)]))
}
