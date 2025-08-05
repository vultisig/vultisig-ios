//
//  OnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI
import RiveRuntime

struct OnboardingView: View {
    
    @EnvironmentObject var accountViewModel: AccountViewModel
    
    @State var tabIndex = 0
    
    @State var showOnboarding = false
    @State var showStartupText = false
    @State var startupTextOpacity = true
    @State var showSummary = false
    
    @State var animationScale: CGFloat = .zero
    
    @State var animationVM: RiveViewModel? = nil
    
#if os(iOS)
    @State var orientation = UIDevice.current.orientation
#endif
    
    let totalTabCount: Int = 6
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            
            if showOnboarding {
                view
            } else {
                startupText
            }
        }
        .onLoad {
            resetOnboarding()
        }
        .onChange(of: showOnboarding) { _, showOnboarding in
            guard !showOnboarding else { return }
            resetOnboarding()
        }
        .onChange(of: tabIndex) { _, _ in
            playAnimation()
        }
        .onDisappear {
            animationVM?.stop()
        }
        .sheet(isPresented: $showSummary) {
            OnboardingSummaryView(kind: .initial, isPresented: $showSummary, onDismiss: {
                accountViewModel.showOnboarding = false
            })
        }
    }
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            skipButton
        }
        .padding(16)
    }
    
    var backButton: some View {
        Button {
            backTapped()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.backward")
                Text(NSLocalizedString("back", comment: ""))
            }
            .foregroundColor(.neutral0)
            .font(Theme.fonts.bodyLMedium)
            .contentShape(Rectangle())
        }
    }
    
    var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                Rectangle()
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(index <= tabIndex ? .turquoise400 : .blue400)
                    .animation(.easeInOut, value: tabIndex)
            }
        }
        .padding(.horizontal, 16)
    }
    
    var nextButton: some View {
        IconButton(icon: "chevron.right") {
            nextTapped()
        }
        .frame(width: 80)
        .padding(.bottom, getBottomPadding())
    }
    
    var skipButton: some View {
        Button {
            skipTapped()
        } label: {
            Text(NSLocalizedString("skip", comment: ""))
                .foregroundColor(Color.extraLightGray)
                .font(Theme.fonts.bodySMedium)
        }
    }
    
    var startupText: some View {
        Group {
            Text(NSLocalizedString("sayGoodbyeTo", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("seedPhrases", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(Theme.fonts.title1)
        .multilineTextAlignment(.center)
        .opacity(showStartupText ? 1 : 0)
        .offset(y: showStartupText ? 0 : 100)
        .blur(radius: showStartupText ? 0 : 10)
        .scaleEffect(showStartupText ? 1 : 0.8)
        .animation(.spring, value: showStartupText)
        .opacity(startupTextOpacity ? 1 : 0)
        .animation(.easeInOut, value: startupTextOpacity)
        .onAppear {
            setupStartupText()
        }
    }
}

private extension OnboardingView {
    func nextTapped() {
        guard tabIndex < totalTabCount - 1 else {
            showSummary = true
            return
        }
        
        tabIndex += 1
    }
    
    func backTapped() {
        showOnboarding = false
    }
    
    func skipTapped() {
        showSummary = true
    }
    
    func moveToVaultView() {
        accountViewModel.showOnboarding = false
    }
    
    func setupStartupText() {
        startupTextOpacity = true
        showStartupText = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            startupTextOpacity = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showOnboarding = true
        }
    }
    
    func playAnimation() {
        animationVM?.setInput("Index", value: Double(tabIndex))
    }
    
    func resetOnboarding() {
        tabIndex = 0
        animationVM?.stop()
        animationVM = RiveViewModel(fileName: "Onboarding", stateMachineName: "State Machine 1")
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AccountViewModel())
}
