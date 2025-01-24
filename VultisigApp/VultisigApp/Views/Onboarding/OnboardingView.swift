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
    
    let animationVM = RiveViewModel(fileName: "Onboarding", animationName: "Screen 1")
    
    let totalTabCount: Int = 6
    
    var body: some View {
        container
    }
    
    var content: some View {
        ZStack {
            Background()
            animation
            view
        }
        .onChange(of: tabIndex) { oldValue, newValue in
            animationVM.play(animationName: "Screen \(tabIndex+1)")
        }
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
    
    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(index: index, animationVM: animationVM)
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
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
        guard tabIndex<totalTabCount-1 else {
            moveToVaultView()
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
}

#Preview {
    OnboardingView()
        .environmentObject(AccountViewModel())
}
