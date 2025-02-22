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

    @State var animationVM: RiveViewModel? = nil
    
    let totalTabCount: Int = 6
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            
            if showOnboarding {
                animation
                view
            } else {
                startupText
            }
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "Onboarding", stateMachineName: "State Machine 1")
        }
        .onChange(of: tabIndex) { oldValue, newValue in
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
    
    var animation: some View {
        animationVM?.view()
    }
    
    var view: some View {
        VStack(spacing: 0) {
            header
            progressBar
            Spacer()
            text
            button
        }
    }
    
    var header: some View {
        HStack {
            headerTitle
            Spacer()
            skipButton
        }
        .padding(16)
    }
    
    var headerTitle: some View {
        Text(NSLocalizedString("intro", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
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
        Button {
            nextTapped()
        } label: {
            FilledButton(icon: "chevron.right")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .frame(width: 80)
        .padding(.bottom, getBottomPadding())
    }
    
    var skipButton: some View {
        Button {
            skipTapped()
        } label: {
            Text(NSLocalizedString("skip", comment: ""))
                .foregroundColor(Color.extraLightGray)
                .font(.body14BrockmannMedium)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var startupText: some View {
        Group {
            Text(NSLocalizedString("sayGoodbyeTo", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("seedPhrases", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(.body28BrockmannMedium)
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
    
    private func nextTapped() {
        guard tabIndex<totalTabCount-1 else {
            showSummary = true
            return
        }
        
        tabIndex+=1
    }

    func skipTapped() {
        moveToVaultView()
    }


    private func moveToVaultView() {
        accountViewModel.showOnboarding = false
    }

    private func setupStartupText() {
        showStartupText = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            startupTextOpacity = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showOnboarding = true
        }
    }
    
    private func playAnimation() {
        animationVM?.setInput("Index", value: Double(tabIndex))
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AccountViewModel())
}
