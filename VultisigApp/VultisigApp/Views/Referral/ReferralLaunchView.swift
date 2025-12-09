//
//  ReferralLaunchView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-29.
//

import SwiftUI

struct ReferralLaunchView: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    @ObservedObject var referralViewModel: ReferralViewModel
    
    @StateObject var keyboardObserver = KeyboardObserver()
    @State var scrollViewProxy: ScrollViewProxy?
    @State var screenHeight: CGFloat = 0
    
    private let referralSavePercentage: String = "10%"
    private let referralSavePercentage2: String = "20%"
    private let scrollToReferenceId = "scrollTo"
    
    @EnvironmentObject var appViewModel: AppViewModel
    
    var isLoading: Bool {
        referredViewModel.isLoading || referralViewModel.isLoading
    }
    
    var body: some View {
        Screen(title: "vultisig-referrals".localized) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            image
                            Spacer()
                            VStack(spacing: 16) {
                                referredContent
                                    .id(scrollToReferenceId)
                                orSeparator
                                referralContent
                            }
                        }
                        .frame(maxHeight: screenHeight)
                    }
                    .onLoad {
                        screenHeight = geo.size.height
                        scrollViewProxy = proxy
                    }
                }
            }
        }
        .overlay(referredViewModel.isLoading ? Loader() : nil)
        .onAppear {
            referralViewModel.currentVault = appViewModel.selectedVault
            referredViewModel.setData()
        }
        .onDisappear {
            referredViewModel.clearFormMessages()
        }
        .onChange(of: referralViewModel.currentVault) { _, _ in
            // TODO: - Remove after release
            referredViewModel.migrateCodeIfNeeded()
            Task {
                await referralViewModel.fetchVaultData()
            }
        }
        #if os(iOS)
        .onChange(of: keyboardObserver.keyboardHeight) { _, height in
            guard height > 250 else {
                return
            }
            
            withAnimation {
                scrollViewProxy?.scrollTo(scrollToReferenceId, anchor: .bottom)
            }
        }
        #endif
    }
    
    var orSeparator: some View {
        HStack(spacing: 16) {
            separator
            
            Text(NSLocalizedString("or", comment: "").uppercased())
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            separator
        }
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var image: some View {
        Image("ReferralLaunchOverview")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 365)
    }
    
    var referredContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    HighlightedText(
                        text: String(format: "referredSaveOnSwaps".localized, referralSavePercentage),
                        highlightedText: referralSavePercentage
                    ) {
                        $0.font = Theme.fonts.bodySMedium
                        $0.foregroundColor = Theme.colors.textPrimary
                    } highlightedTextStyle: {
                        $0.foregroundColor = Theme.colors.primaryAccent4
                    }
                }
                
                referredTextField
            }

            referredCodeButton
        }
    }
}

// MARK: - Referred

private extension ReferralLaunchView {
    var referredCodeButton: some View {
        PrimaryButton(title: referredViewModel.referredButtonTitle, type: .secondary) {
            Task { @MainActor in
                await referredViewModel.verifyAndSaveReferredCode()
            }
        }
        .disabled(referredViewModel.referredButtonDisabled)
    }
    
    var referredTextField: some View {
        ReferralTextField(
            text: $referredViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            errorMessage: $referredViewModel.referredLaunchViewErrorMessage
        )
    }
}

// MARK: - Referral

private extension ReferralLaunchView {
    var referralContent: some View {
        VStack(spacing: 16) {
            referralTitle
            if referralViewModel.hasReferralCode {
                editReferralButton
            } else {
                createReferralButton
            }
        }
    }
    
    var referralTitle: some View {
        HighlightedText(
            text: String(format: "createYourCodeAndEarn".localized, referralSavePercentage2),
            highlightedText: referralSavePercentage2
        ) {
            $0.font = Theme.fonts.bodySMedium
            $0.foregroundColor = Theme.colors.textPrimary
        } highlightedTextStyle: {
            $0.foregroundColor = Theme.colors.primaryAccent4
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var createReferralButton: some View {
        PrimaryNavigationButton(title: "createReferral") {
            ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: false)
        }
    }
    
    var editReferralButton: some View {
        PrimaryNavigationButton(title: "editReferral") {
            ReferralMainScreen(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        }
    }
}

#Preview {
    ReferralLaunchView(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
        .environmentObject(AppViewModel())
}
