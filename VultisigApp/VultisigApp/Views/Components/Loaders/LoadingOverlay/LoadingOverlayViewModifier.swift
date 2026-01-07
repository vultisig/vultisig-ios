//
//  LoadingOverlayViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct LoadingOverlayViewModifier: ViewModifier {
    let text: String
    @Binding var isLoading: Bool
    @State private var isLoadingInternal: Bool = false
    
    func body(content: Content) -> some View {
        content
            .overlay(overlay)
            .onChange(of: isLoading) { _, newValue in
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15)) {
                    isLoadingInternal = newValue
                }
            }
        
    }
    
    @ViewBuilder
    var overlay: some View {
        if isLoadingInternal {
            ZStack {
                Theme.colors.bgPrimary.opacity(0.4).ignoresSafeArea()
                LoadingBanner(text: text, isVisible: $isLoadingInternal)
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}

private struct LoadingBanner: View {
    let text: String
    @Binding var isVisible: Bool
    @State private var progress: Double = 0.0
    @State var isVisibleInternal: Bool = false
    
    let animation: Animation = .interpolatingSpring(mass: 1, stiffness: 100, damping: 15)
    
    var body: some View {
        VStack {
            VStack(spacing: 8) {
                CircularProgressIndicator(size: 18, tint: Theme.colors.alertSuccess)
                Text(text)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 24)
                .inset(by: 0.5)
                .stroke(Theme.colors.border, lineWidth: 1)
                .fill(Theme.colors.bgSurface1)
            )
            .scaleEffect(isVisibleInternal ? 1.0 : 0.8)
            .opacity(isVisibleInternal ? 1.0 : 0.0)
            .animation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15), value: isVisibleInternal)
            .onAppear {
                withAnimation(animation.repeatForever(autoreverses: false)) {
                    progress = 1.0
                }
            }
        }
        .padding(.horizontal, 12)
        .onAppear {
            withAnimation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15)) {
                isVisibleInternal = true
            }
        }
    }
}

extension View {
    func withLoading(text: String = "pleaseWait".localized, isLoading: Binding<Bool>) -> some View {
        modifier(LoadingOverlayViewModifier(text: text, isLoading: isLoading))
    }
}
