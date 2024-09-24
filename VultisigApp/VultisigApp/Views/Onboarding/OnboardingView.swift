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
    
    init() {
         tabViewSetup()
    }
    
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
    
    var nextButton: some View {
        Button {
            nextTapped()
        } label: {
            FilledButton(title: "next")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
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
        .opacity(tabIndex==3 ? 0 : 1)
        .disabled(tabIndex==3 ? true : false)
        .animation(.easeInOut, value: tabIndex)
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    private func nextTapped() {
        guard tabIndex<3 else {
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
