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
        case name, email, password, passwordConfirm
    }
    
    @StateObject var viewModel: VaultSetupViewModel
    
    @State private var currentStep = 0
    @State private var navigatingForward = true
    @State private var showReferralSheet = false
    @State private var showPasswordTooltip = false
    @FocusState private var focusedField: FocusedField?
    @Environment(\.router) var router
    
    init(tssType: TssType, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType? = nil) {
        self.tssType = tssType
        self.keyImportInput = keyImportInput
        self.setupType = setupType ?? .fast
        _viewModel = StateObject(wrappedValue: VaultSetupViewModel(setupType: setupType ?? .fast))
    }
    
    private var stepIcons: [String] {
        var icons = ["feather"]
        if viewModel.showFastSignFields {
            icons.append(contentsOf: ["email", "focus-lock"])
        }
        return icons
    }
    
    private var totalSteps: Int { stepIcons.count }
    private var isLastStep: Bool { currentStep >= totalSteps - 1 }
    
    private var isCurrentStepValid: Bool {
        isStepValid(at: currentStep)
    }

    private func isStepValid(at step: Int) -> Bool {
        switch step {
        case 0:
            return viewModel.nameField.valid
        case 1:
            return viewModel.emailField.valid
        case 2:
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
                
                PrimaryButton(
                    title: isLastStep && isCurrentStepValid
                    ? "createVault".localized
                    : "next".localized
                ) {
                    onContinue()
                }
            }
            .overlay(alignment: .top) {
                if showPasswordTooltip {
                    tooltipOverlay
                }
            }
        }
        .crossPlatformToolbar(showsBackButton: false) {
            CustomToolbarItem(placement: .trailing, hideSharedBackground: true) {
                referralButton
            }
        }
        .crossPlatformSheet(isPresented: $showReferralSheet) {
            ReferralCodeSheet(
                isPresented: $showReferralSheet,
                viewModel: viewModel
            )
            .sheetStyle()
            .applySheetSize()
        }
        .onLoad {
            viewModel.onLoad()
            focusedField = .name
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
                nameStep
            case 1:
                emailStep
            case 2:
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
    
    private var nameStep: some View {
        VStack(spacing: 20) {
            stepHeader(
                title: "nameYourVault".localized,
                subtitle: "newWalletNameDescription".localized
            )

            CommonTextField(
                text: $viewModel.nameField.value,
                placeholder: viewModel.nameField.placeholder,
                error: $viewModel.nameField.error,
                isValid: isValidBinding(for: viewModel.nameField)
            )
            .focused($focusedField, equals: .name)
        }
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
            passwordStepHeader
            
            VStack(spacing: 16) {
                SecureTextField(
                    value: $viewModel.passwordField.value,
                    placeholder: viewModel.passwordField.placeholder,
                    error: $viewModel.passwordField.error,
                    isValid: isValidBinding(for: viewModel.passwordField)
                )
                .focused($focusedField, equals: .password)
                
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
    
    private var passwordStepHeader: some View {
        VStack(spacing: 12) {
            Text("chooseAPassword".localized)
                .font(Theme.fonts.title1)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
            
            passwordSubtitle
        }
    }
    
    private var passwordSubtitle: some View {
        var attributed = AttributedString("choosePasswordDescription".localized)
        attributed.font = Theme.fonts.bodySMedium
        attributed.foregroundColor = Theme.colors.textTertiary
        
        if let range = attributed.range(of: "choosePasswordHighlight".localized) {
            attributed[range].foregroundColor = Theme.colors.textPrimary
        }
        
        return (
            Text(attributed) + Text(" \(Image(systemName: "info.circle.fill"))")
                .foregroundStyle(Theme.colors.textPrimary)
                .font(.callout)
        )
        .multilineTextAlignment(.center)
        .onTapGesture {
            withAnimation(.interpolatingSpring) {
                showPasswordTooltip.toggle()
            }
        }
    }
    
    private var tooltipOverlay: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.interpolatingSpring) {
                        showPasswordTooltip = false
                    }
                }
            
            Tooltip(text: "choosePasswordTooltip".localized)
                .padding(.top, 180)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        }
    }
    
    private func isValidBinding(for field: FormField) -> Binding<Bool?> {
        Binding<Bool?>(
            get: { field.touched ? field.valid : nil },
            set: { _ in }
        )
    }
    
    // MARK: - Referral Button

    private var referralButton: some View {
        Button {
            showReferralSheet = true
        } label: {
            referralButtonLabel
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.colors.bgSurface2)
                .stroke(Theme.colors.borderExtraLight.opacity(0.3), lineWidth: 1)
        )
    }

    private var referralButtonLabel: some View {
        HStack(spacing: 4) {
            if !viewModel.referralField.value.isEmpty && viewModel.referralField.valid {
                Icon(
                    named: "check",
                    color: Theme.colors.alertSuccess,
                    size: 16
                )

                Text("referralAdded".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
            } else {
                Text("addReferral".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
            let selectedTab: SetupVaultState = setupType == .fast ? .fast : .secure
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: tssType,
                vault: viewModel.getVault(keyImportInput: keyImportInput),
                selectedTab: selectedTab,
                fastSignConfig: viewModel.showFastSignFields ? viewModel.fastConfig : nil,
                keyImportInput: keyImportInput,
                setupType: setupType
            ))
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
            case 0: focusedField = .name
            case 1: focusedField = .email
            case 2: focusedField = .password
            default: break
            }
        }
    }
}

#Preview {
    VaultSetupScreen(
        tssType: .KeyImport,
        keyImportInput: .init(mnemonic: "test", chainSettings: [ChainImportSetting(chain: .bitcoin)])
    )
}
