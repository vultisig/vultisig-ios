//
//  OnboardingView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension OnboardingView {
    init() {
       UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Color.turquoise600)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Color.turquoise600).withAlphaComponent(0.2)
   }
    
    var container: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
    }
    
    var tabs: some View {
        TabView(selection: $tabIndex) {
            OnboardingView1().tag(0)
            OnboardingView2().tag(1)
            OnboardingView3().tag(2)
            OnboardingView4().tag(3)
        }
        .tabViewStyle(PageTabViewStyle())
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
}
#endif
