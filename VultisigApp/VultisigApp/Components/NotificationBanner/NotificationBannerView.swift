//
//  NotificationBannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct NotificationBannerView: View {
    let text: String
    @State private var progress: Double = 0.0
    @Binding var isVisible: Bool
    @State var isVisibleInternal: Bool = false

    let animation: Animation = .interpolatingSpring(mass: 1, stiffness: 100, damping: 15)
    private let duration: Double = 1.3
    private let progressDelay: CGFloat = 0.1

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Theme.colors.border, lineWidth: 2)
                        .frame(width: 18, height: 18)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.colors.alertSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .rotationEffect(.radians(-.pi / 2))
                        .animation(animation.delay(progressDelay), value: progress)
                    Icon(named: "check", color: Theme.colors.alertSuccess, size: 9)
                }

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
                progress = 1.0

                DispatchQueue.main.asyncAfter(deadline: .now() + duration + progressDelay) {
                    withAnimation(animation) {
                        isVisibleInternal = false
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isVisible = false
                    }
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

#Preview {
    VStack {
        Spacer()
        NotificationBannerView(text: "Address copied", isVisible: .constant(true))
            .padding(.horizontal, 16)
        Spacer()
    }
    .background(Color.black)
}
