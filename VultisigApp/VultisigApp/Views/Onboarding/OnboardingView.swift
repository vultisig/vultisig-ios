//
//  OnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI

struct OnboardingView: View {
    @State var tabIndex = 0
    @EnvironmentObject var accountViewModel: AccountViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }
    
    var view: some View {
        VStack {
            title
            tabs
            buttons
        }
    }
    
    var title: some View {
        Image("LogoWithTitle")
            .padding(.top, 30)
    }
    
    var tabs: some View {
        TabView(selection: $tabIndex) {
            OnboardingView1().tag(0)
            OnboardingView2().tag(1)
            OnboardingView3().tag(2)
        }
#if os(iOS)
        .tabViewStyle(PageTabViewStyle())
#endif
        .frame(maxHeight: .infinity)
    }
    
    var buttons: some View {
        VStack(spacing: 15) {
            nextButton
            skipButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }
    
    var nextButton: some View {
        Button {
            nextTapped()
        } label: {
            FilledButton(title: "next")
        }
    }
    
    var skipButton: some View {
        Button {
            skipTapped()
        } label: {
            Text(NSLocalizedString("skip", comment: ""))
                .padding(12)
                .frame(maxWidth: .infinity)
                .foregroundColor(Color.turquoise600)
                .font(.body16MontserratMedium)
        }
        .opacity(tabIndex==2 ? 0 : 1)
        .disabled(tabIndex==2 ? true : false)
        .animation(.easeInOut, value: tabIndex)
    }
    
    private func nextTapped() {
        guard tabIndex<2 else {
            moveToVaultView()
            return
        }
        
        withAnimation {
            tabIndex+=1
        }
    }
    
    private func skipTapped() {
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
