//
//  ErrorView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/08/2025.
//

import SwiftUI

struct ErrorScreen: View {
    let type: ErrorView.ErrorType
    let title: String
    let description: String
    let buttonTitle: String
    var secondaryButtonTitle: String?
    var rawError: String?
    var action: () -> Void
    var secondaryAction: (() -> Void)?

    var body: some View {
        Screen {
            ErrorView(
                type: type,
                title: title,
                description: description,
                buttonTitle: buttonTitle,
                secondaryButtonTitle: secondaryButtonTitle,
                rawError: rawError,
                action: action,
                secondaryAction: secondaryAction
            )
        }
    }
}

/// Shared friendly error screen: a concentric-circle hero with a state icon,
/// a human title and a fix-it subtitle. When a raw technical error is present,
/// a "Show exact error" disclosure opens a full-screen sheet with the trace
/// (copyable + reportable). The primary CTA is bottom-pinned.
struct ErrorView: View {
    let type: ErrorType
    let title: String
    let description: String
    let buttonTitle: String
    var secondaryButtonTitle: String?
    var rawError: String?
    var action: () -> Void
    var secondaryAction: (() -> Void)?

    @State private var showRawError = false
    @State private var didAppear = false
    @State private var showText = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        hero
                        Text(title)
                            .foregroundStyle(color)
                            .font(Theme.fonts.title2)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        if description.isNotEmpty {
                            Text(description)
                                .foregroundStyle(Theme.colors.textTertiary)
                                .font(Theme.fonts.bodySMedium)
                                .multilineTextAlignment(.center)
                                .opacity(textOpacity)
                        }
                        if let rawError, rawError.isNotEmpty {
                            showExactErrorRow
                                .padding(.top, 12)
                                .opacity(textOpacity)
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: 12) {
                PrimaryButton(title: buttonTitle, type: .primary, action: action)
                if let secondaryButtonTitle, let secondaryAction {
                    PrimaryButton(title: secondaryButtonTitle, type: .secondary, action: secondaryAction)
                }
                Text(Bundle.main.appVersionString)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
                    .opacity(0.6)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
        .crossPlatformSheet(isPresented: $showRawError) {
            ErrorMessageSheet(rawError: rawError ?? .empty, isPresented: $showRawError)
        }
        .onAppear { animateEntrance() }
    }
}

private extension ErrorView {
    func animateEntrance() {
        guard !didAppear else { return }
        guard !reduceMotion else {
            didAppear = true
            showText = true
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            didAppear = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.15)) {
            showText = true
        }
    }

    var hero: some View {
        Image(systemName: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .foregroundStyle(color)
            .animation(.easeInOut(duration: 0.3), value: type)
            .background(Image("CirclesBackground"))
            .padding(.bottom, 12)
            .scaleEffect(heroScale)
            .opacity(heroOpacity)
    }

    var showExactErrorRow: some View {
        Button {
            showRawError = true
        } label: {
            HStack(spacing: 12) {
                Text("errorShowExact".localized)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .font(Theme.fonts.bodySMedium)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .rotationEffect(Angle(degrees: showRawError ? 180 : 0))
                    .animation(.easeInOut, value: showRawError)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var heroScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return didAppear ? 1 : 0.7
    }

    var heroOpacity: Double {
        didAppear ? 1 : 0
    }

    var textOpacity: Double {
        guard !reduceMotion else { return 1 }
        return showText ? 1 : 0
    }

    var icon: String {
        switch type {
        case .warning:
            return "exclamationmark.circle.fill"
        case .alert:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch type {
        case .alert:
            Theme.colors.alertError
        case .warning:
            Theme.colors.alertWarning
        }
    }
}

extension ErrorView {
    /// Visual variant of the error hero.
    /// - `alert`: hard failure — red ✕.
    /// - `warning`: recoverable / precondition error — amber ⚠.
    enum ErrorType {
        case alert
        case warning
    }
}

#Preview {
    ErrorView(
        type: .alert,
        title: "Transaction failed",
        description: "One of your devices didn't respond in time. Check your connection and try again.",
        buttonTitle: "Try Again",
        rawError: "javax.crypto.AEADBadTagException: error:1e000065:Cipher functions"
    ) {}
}
