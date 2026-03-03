//
//  FastVaultPasswordScreen.swift
//  VultisigApp
//

import SwiftUI

struct FastVaultPasswordScreen: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState
    let isExistingVault: Bool

    enum FocusedField {
        case email, password, passwordConfirm
    }

    @StateObject private var viewModel: FastVaultPasswordViewModel
    @State private var currentStep = 0
    @State private var navigatingForward = true
    @FocusState private var focusedField: FocusedField?
    @Environment(\.router) var router

    init(tssType: TssType, vault: Vault, selectedTab: SetupVaultState, isExistingVault: Bool) {
        self.tssType = tssType
        self.vault = vault
        self.selectedTab = selectedTab
        self.isExistingVault = isExistingVault
        _viewModel = StateObject(wrappedValue: FastVaultPasswordViewModel(isExistingVault: isExistingVault))
    }

    private let stepIcons = ["email", "focus-lock"]
    private var totalSteps: Int { stepIcons.count }
    private var isLastStep: Bool { currentStep >= totalSteps - 1 }

    private var isCurrentStepValid: Bool {
        isStepValid(at: currentStep)
    }

    private func isStepValid(at step: Int) -> Bool {
        switch step {
        case 0:
            return viewModel.emailField.valid
        case 1:
            if isExistingVault {
                return viewModel.passwordField.valid
            }
            return viewModel.passwordField.valid
            && viewModel.passwordConfirmField.valid
        default:
            return false
        }
    }

    private func canNavigateToStep(_ target: Int) -> Bool {
        guard target >= 0, target < totalSteps, target != currentStep else { return false }
        return (0..<target).allSatisfy { isStepValid(at: $0) }
    }

    // MARK: - Body

    var body: some View {
        Screen(edgeInsets: .init(leading: 24, trailing: 24)) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepIndicator
                            .padding(.top, 24)
                            .padding(.bottom, 24)

                        stepContent
                    }
                }

                Spacer()

                PrimaryButton(title: "next".localized) {
                    onContinue()
                }
            }
        }
        .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $viewModel.isWrongPassword) {
            Button("OK", role: .cancel) { }
        }
        .withLoading(isLoading: $viewModel.isLoading)
        .onLoad {
            viewModel.onLoad()
            focusedField = .email
        }
        .onSubmit {
            onContinue()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(Array(stepIcons.enumerated()), id: \.offset) { index, icon in
                if index > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.colors.border)
                        .frame(width: 16, height: 1)
                }
                Button {
                    navigateToStep(index)
                } label: {
                    VaultSetupStepIcon(state: stepState(for: index), icon: icon)
                }
                .buttonStyle(.plain)
                .disabled(!canNavigateToStep(index))
            }
        }
    }

    private func stepState(for index: Int) -> VaultSetupStepState {
        if index < currentStep { return .valid }
        if index == currentStep { return .active }
        return .inactive
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0:
                emailStep
            case 1:
                passwordStep
            default:
                EmptyView()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
        ))
    }

    private var emailStep: some View {
        VStack(spacing: 20) {
            stepHeader(
                title: "enterYourEmail".localized,
                subtitle: "enterVaultEmail".localized
            )

            CommonTextField(
                text: $viewModel.emailField.value,
                placeholder: viewModel.emailField.placeholder ?? .empty,
                error: $viewModel.emailField.error,
                isValid: isValidBinding(for: viewModel.emailField)
            )
            .focused($focusedField, equals: .email)
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
#endif
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 20) {
            stepHeader(
                title: "chooseAPassword".localized,
                subtitle: "enterYourVaultsPassword".localized
            )

            VStack(spacing: 16) {
                SecureTextField(
                    value: $viewModel.passwordField.value,
                    placeholder: viewModel.passwordField.placeholder,
                    error: $viewModel.passwordField.error,
                    isValid: isValidBinding(for: viewModel.passwordField)
                )
                .focused($focusedField, equals: .password)

                if !isExistingVault {
                    SecureTextField(
                        value: $viewModel.passwordConfirmField.value,
                        placeholder: viewModel.passwordConfirmField.placeholder,
                        error: $viewModel.passwordConfirmField.error,
                        isValid: isValidBinding(for: viewModel.passwordConfirmField)
                    )
                    .focused($focusedField, equals: .passwordConfirm)
                }
            }
        }
    }

    // MARK: - Headers

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(Theme.fonts.title1)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isValidBinding(for field: FormField) -> Binding<Bool?> {
        Binding<Bool?>(
            get: { field.touched ? field.valid : nil },
            set: { _ in }
        )
    }

    // MARK: - Actions

    private func navigateToStep(_ target: Int) {
        guard canNavigateToStep(target) else { return }

        focusedField = nil
        navigatingForward = target > currentStep

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = target
        }
        focusNextStepField()
    }

    private func onContinue() {
        guard isCurrentStepValid else { return }

        if isLastStep {
            viewModel.validateErrors()
            guard viewModel.validForm else { return }

            if isExistingVault {
                Task {
                    let isValid = await viewModel.checkPassword(pubKeyECDSA: vault.pubKeyECDSA)
                    if isValid {
                        navigateToPeerDiscovery()
                    }
                }
            } else {
                navigateToPeerDiscovery()
            }
        } else {
            focusedField = nil
            navigatingForward = true

            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
            focusNextStepField()
        }
    }

    private func focusNextStepField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            switch currentStep {
            case 0: focusedField = .email
            case 1: focusedField = .password
            default: break
            }
        }
    }

    private func navigateToPeerDiscovery() {
        router.navigate(to: KeygenRoute.peerDiscovery(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastSignConfig: viewModel.fastSignConfig,
            keyImportInput: nil,
            setupType: nil,
            singleKeygenType: nil
        ))
    }
}
