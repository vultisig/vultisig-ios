//
//  OnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI
import RiveRuntime

struct OnboardingView: View {
    @State var tabIndex = 0
    @EnvironmentObject var accountViewModel: AccountViewModel
    
    let animationVM = RiveViewModel(fileName: "Onboarding", autoPlay: false)
    
    let totalTabCount: Int = 6
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            view
        }
    }
    
    var view: some View {
        VStack(spacing: 0) {
            header
            progressBar
            animation
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
            ForEach(0..<totalTabCount) { index in
                Rectangle()
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(index <= tabIndex ? .turquoise400 : .blue400)
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
    
    private func nextTapped() {
        animationVM.pause()
        guard tabIndex<totalTabCount else {
            moveToVaultView()
            return
        }
        
        withAnimation(.easeOut(duration: 0.1)) {
            tabIndex+=1
            animationVM.play()
        }
    }
    
    func skipTapped() {
        moveToVaultView()
    }
    
    private func moveToVaultView() {
        accountViewModel.showOnboarding = false
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AccountViewModel())
}
