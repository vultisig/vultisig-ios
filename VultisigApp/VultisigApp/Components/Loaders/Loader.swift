//
//  Loader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-21.
//

import SwiftUI

struct Loader: View {
    var body: some View {
        ZStack {
            overlay
            loader
        }
    }

    var overlay: some View {
        Color.black
            .ignoresSafeArea()
            .opacity(0.3)
    }

    var loader: some View {
        VStack(spacing: 20) {
            SpinningLineLoader()
                .scaleEffect(1.5)

            Text(NSLocalizedString("pleaseWait", comment: ""))
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(width: 180, height: 120)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
}

// MARK: - Non-blocking Loaders

struct InlineLoader: View {
    var body: some View {
        SpinningLineLoader()
            .scaleEffect(0.6)
            .frame(width: 24, height: 24)
    }
}

struct SpinningLineLoader: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Blue background circle
            Circle()
                .fill(Theme.colors.bgSurface1) // Using hex value for blue600
                .frame(width: 32, height: 32)

            // White spinning arc - much shorter like in SwapRefreshQuoteCounter
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 20, height: 20)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(
                    Animation.linear(duration: 1)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct ButtonLoader: View {
    var body: some View {
        SpinningLineLoader()
            .frame(width: 32, height: 32)
    }
}

struct SwapLoader: View {
    var body: some View {
        SpinningLineLoader()
            .scaleEffect(1.2)
            .frame(width: 60, height: 60)
            .background(Theme.colors.bgSurface1.opacity(0.9))
            .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        Loader()
        InlineLoader()
        ButtonLoader()
        SwapLoader()
        SpinningLineLoader()
    }
}
