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
    
#if os(iOS)
    init() {
       UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Color.turquoise600)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Color.turquoise600).withAlphaComponent(0.2)
   }
#endif
    
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
#if os(iOS)
        TabView(selection: $tabIndex) {
            OnboardingView1().tag(0)
            OnboardingView2().tag(1)
            OnboardingView3().tag(2)
            OnboardingView4().tag(3)
        }
        .tabViewStyle(PageTabViewStyle())
        .frame(maxHeight: .infinity)
#elseif os(macOS)
        ZStack {
            switch tabIndex {
            case 0:
                OnboardingView1(tabIndex: $tabIndex)
            case 1:
                OnboardingView2(tabIndex: $tabIndex)
            case 2:
                OnboardingView3(tabIndex: $tabIndex)
            default:
                OnboardingView4(tabIndex: $tabIndex)
            }
        }
#endif
    }
    
    var buttons: some View {
        VStack(spacing: 15) {
#if os(iOS)
            nextButton
            skipButton
#elseif os(macOS)
            setupVaultButton
#endif
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
    
#if os(macOS)
    var setupVaultButton: some View {
        Button {
            skipTapped()
        } label: {
            FilledButton(title: "setupVault")
        }
        .animation(.easeInOut, value: tabIndex)
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .padding(.bottom, 40)
    }
#endif
    
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
