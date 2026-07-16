//
//  NotificationBannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

enum NotificationBannerStyle: CaseIterable {
    case success
    case error

    var iconName: String {
        switch self {
        case .success: "check"
        case .error: "x"
        }
    }

    var accentColor: Color {
        switch self {
        case .success: Theme.colors.alertSuccess
        case .error: Theme.colors.alertError
        }
    }
}

struct NotificationBannerView: View {
    let text: String
    let style: NotificationBannerStyle
    @State private var progress: Double = 0.0
    @Binding var isVisible: Bool
    @State var isVisibleInternal: Bool = false
    @State private var dismissalTask: Task<Void, Never>?

    let animation: Animation = .interpolatingSpring(mass: 1, stiffness: 100, damping: 15)
    private let duration: Double = 1.3
    private let progressDelay: CGFloat = 0.1

    init(
        text: String,
        style: NotificationBannerStyle = .success,
        isVisible: Binding<Bool>
    ) {
        self.text = text
        self.style = style
        self._isVisible = isVisible
    }

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
                        .stroke(style.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .rotationEffect(.radians(-.pi / 2))
                        .animation(animation.delay(progressDelay), value: progress)
                    Icon(named: style.iconName, color: style.accentColor, size: 9)
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
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 15)) {
                    isVisibleInternal = true
                }
                progress = 1.0
                dismissalTask?.cancel()
                dismissalTask = Task { @MainActor in
                    let hideDelay = Int((duration + Double(progressDelay)) * 1000)
                    do {
                        try await Task.sleep(for: .milliseconds(hideDelay))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(animation) {
                        isVisibleInternal = false
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    isVisible = false
                }
            }
        }
        .padding(.horizontal, 12)
        .onDisappear {
            dismissalTask?.cancel()
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Spacer()
        NotificationBannerView(text: "Address copied", isVisible: .constant(true))
            .padding(.horizontal, 16)
        NotificationBannerView(text: "Couldn't refresh", style: .error, isVisible: .constant(true))
            .padding(.horizontal, 16)
        Spacer()
    }
    .background(Color.black)
}
