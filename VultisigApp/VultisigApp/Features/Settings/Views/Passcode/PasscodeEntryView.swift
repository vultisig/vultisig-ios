//
//  PasscodeEntryView.swift
//  VultisigApp
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Settings passcode entry with native iOS keyboard input and hardware-keyboard
/// input on macOS. The visual dots are deliberately separate from the hidden
/// field so a confirmation step can keep the first entry visible above the
/// active row without exposing any digits.
struct PasscodeEntryView: View {

    let title: String
    let subtitle: String?
    var completedPasscode: String?
    var activePrompt: String?
    var errorMessage: String?
    var isBusy: Bool = false
    var isSuccess: Bool = false
    @Binding var passcode: String
    let onComplete: (String) -> Void

    @State private var shakeTravel: CGFloat = 0
    #if os(iOS)
    @FocusState private var isPasscodeFieldFocused: Bool
    #endif

    private var hasError: Bool { errorMessage?.isEmpty == false }

    var body: some View {
        PasscodeInput(
            passcode: $passcode,
            isBusy: isBusy,
            onComplete: onComplete
        ) { _ in
            content
                #if os(iOS)
                .overlay(alignment: .topLeading) {
                    nativePasscodeField
                }
                #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: errorMessage) { _, message in
            guard message?.isEmpty == false else { return }
            reactToError()
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Icon(.lockPassword, color: Theme.colors.primaryAccent4, size: 46)

            VStack(spacing: 14) {
                Text(title)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .id(title)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.fonts.bodySRegular)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(subtitle)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 285)

            if let completedPasscode {
                dots(for: completedPasscode, hasError: false, isSuccess: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            VStack(spacing: 16) {
                if let activePrompt {
                    Text(activePrompt)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                dots(for: passcode, hasError: hasError, isSuccess: isSuccess)
                    .modifier(PasscodeShakeEffect(travel: shakeTravel))

                Text(errorMessage ?? " ")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertError)
                    .multilineTextAlignment(.center)
                    .opacity(hasError ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: errorMessage)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.28), value: title)
        .animation(.easeInOut(duration: 0.28), value: subtitle)
        .animation(.easeInOut(duration: 0.28), value: completedPasscode)
        .animation(.easeInOut(duration: 0.28), value: activePrompt)
        .animation(.easeInOut(duration: 0.2), value: isSuccess)
    }

    private func dots(for value: String, hasError: Bool, isSuccess: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<PasscodeService.passcodeLength, id: \.self) { index in
                let isFilled = index < value.count
                Circle()
                    .fill(isFilled ? dotColor(isSuccess: isSuccess) : Color.clear)
                    .frame(width: 13, height: 13)
                    .overlay {
                        Circle().stroke(
                            hasError ? Theme.colors.alertError : dotColor(isSuccess: isSuccess),
                            lineWidth: 1.5
                        )
                    }
                    .frame(width: 25, height: 25)
                    .scaleEffect(isFilled ? 1 : 0.82)
                    .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isFilled)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasError)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Passcode.dots)
        .accessibilityValue("\(value.count)")
    }

    private func dotColor(isSuccess: Bool) -> Color {
        isSuccess ? Theme.colors.alertSuccess : Theme.colors.textPrimary
    }

    private func reactToError() {
        withAnimation(.linear(duration: 0.4)) {
            shakeTravel += 1
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

#if os(iOS)
private extension PasscodeEntryView {
    var nativePasscodeField: some View {
        SecureField("", text: nativePasscode)
            .keyboardType(.numberPad)
            .textFieldStyle(.plain)
            .foregroundStyle(.clear)
            .tint(.clear)
            .focused($isPasscodeFieldFocused)
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityHidden(true)
            .task { @MainActor in
                await Task.yield()
                isPasscodeFieldFocused = true
            }
            .onChange(of: isBusy) { _, busy in
                guard !busy else { return }
                isPasscodeFieldFocused = true
            }
    }

    var nativePasscode: Binding<String> {
        Binding(
            get: { passcode },
            set: { candidate in
                guard !isBusy,
                      PasscodeInputRules.acceptsNativeEntry(candidate) else {
                    return
                }
                passcode = candidate
            }
        )
    }
}
#endif

/// Shared sheet chrome for set, change, and disable. Closing is driven by the
/// presenter's binding because the pre-macOS-26 cross-platform sheet is an
/// in-place overlay rather than a native presentation.
private struct PasscodeSheetChrome: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var isBusy: Bool

    func body(content: Content) -> some View {
        content
            .screenBackground(.clear)
            .background {
                PasscodeBackground()
                    .ignoresSafeArea()
            }
            .screenBackButtonHidden()
            .screenIgnoresTopEdge()
            .screenToolbar {
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .xmark) {
                        guard !isBusy else { return }
                        isPresented = false
                    }
                    .disabled(isBusy)
                }
            }
            .applySheetSize(650, 700)
            .sheetStyle()
    }
}

extension View {
    func passcodeSheetChrome(
        isPresented: Binding<Bool>,
        isBusy: Binding<Bool>
    ) -> some View {
        modifier(PasscodeSheetChrome(isPresented: isPresented, isBusy: isBusy))
    }
}

struct PasscodeBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.colors.bgPrimary

                Ellipse()
                    .fill(Theme.colors.primaryAccent4)
                    .frame(width: 304, height: 338)
                    .blur(radius: 127)
                    .opacity(0.2)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
            }
        }
    }
}

private struct PasscodeShakeEffect: GeometryEffect {
    var amplitude: CGFloat = 9
    var shakesPerUnit: CGFloat = 3
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amplitude * sin(travel * .pi * shakesPerUnit), y: 0)
        )
    }
}
