//
//  OnboardingView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension OnboardingView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var container: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
    }
    
    @ViewBuilder
    var view: some View {
        animation
        VStack(spacing: 0) {
            header
            progressBar
            text
            button
        }
    }
    
    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(
                        index: index,
                        textPrefix: "OnboardingCard"
                    )
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
    }
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 10)
    }
    
    var animation: some View {
        animationVM?.view()
            .scaleEffect(animationScale)
            .padding(.bottom, 100)
            .onAppear {
                getScale()
            }
            .onChange(of: orientation, { _, _ in
                getScale()
            })
    }
    
    func getBottomPadding() -> CGFloat {
        idiom == .phone ? 0 : 50
    }
    
    private func getScale() {
        let screenWidth = UIScreen.main.bounds.size.width
        
        if screenWidth>1050 && idiom == .pad {
            animationScale = 0.8
        } else {
            animationScale = 1
        }
    }
}
#endif
