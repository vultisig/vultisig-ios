//
//  LockPasscodeEntryView.swift
//  VultisigApp
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LockPasscodeEntryView: View {
    var errorMessage: String?
    var isBusy: Bool
    var isBiometricUnlockAvailable: Bool
    @Binding var passcode: String
    let onComplete: (String) -> Void
    let onBiometricUnlock: () -> Void

    @State private var shakeTravel: CGFloat = 0
    #if os(iOS)
    @FocusState private var isPasscodeFieldFocused: Bool
    #endif

    private var digitCount: Int { PasscodeService.passcodeLength }
    private var hasError: Bool { errorMessage?.isEmpty == false }

    var body: some View {
        ZStack {
            LockScreenBackground()
                .ignoresSafeArea()

            PasscodeInput(
                passcode: $passcode,
                isBusy: isBusy,
                onComplete: onComplete
            ) { actions in
                #if os(iOS)
                lockContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 26)
                    .overlay(alignment: .topLeading) {
                        nativePasscodeField
                    }
                #else
                VStack(spacing: 0) {
                    lockContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 26)

                    LockPasscodeKeypad(
                        isBusy: isBusy,
                        actions: actions
                    )
                    .frame(height: 310)
                }
                #endif
            }
        }
        #if os(iOS)
        .ignoresSafeArea(.container)
        #else
        .ignoresSafeArea()
        #endif
        .onChange(of: errorMessage) { _, message in
            guard message?.isEmpty == false else { return }
            reactToError()
        }
    }

    private var lockContent: some View {
        VStack(spacing: 0) {
            Image("vultisig-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 47.5, height: 47.5)

            header
                .padding(.top, 34.5)

            passcodeField
                .padding(.top, 36)

            biometricButton
                .padding(.top, 35)
        }
        .frame(maxWidth: 328)
    }

    private var header: some View {
        VStack(spacing: 16) {
            Text("passcodeEnterTitle".localized)
                .font(Theme.fonts.largeTitle)
                .tracking(-1)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(height: 37)

            Text("passcodeEnterSubtitle".localized)
                .font(Theme.fonts.footnote)
                .tracking(0.06)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(height: 18)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var passcodeField: some View {
        HStack(spacing: 10) {
            ForEach(0..<digitCount, id: \.self) { index in
                passcodeDot(isFilled: index < passcode.count)
                    .frame(width: 25, height: 25)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 77)
        .background(Theme.colors.lockPasscodeField)
        .overlay {
            Theme.radius.xl.shape
                .stroke(Theme.colors.buttonBevelLight, lineWidth: 1)
        }
        .clipShape(Theme.radius.xl.shape)
        .modifier(LockShakeEffect(travel: shakeTravel))
        .overlay(alignment: .bottom) {
            Text(errorMessage ?? " ")
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.alertError)
                .lineLimit(1)
                .opacity(hasError ? 1 : 0)
                .offset(y: 22)
        }
        .accessibilityIdentifier(AccessibilityID.Passcode.dots)
        .accessibilityValue("\(passcode.count)")
    }

    private func passcodeDot(isFilled: Bool) -> some View {
        Circle()
            .fill(isFilled ? Theme.colors.textPrimary : Color.clear)
            .frame(width: 13, height: 13)
            .overlay {
                Circle().stroke(
                    hasError ? Theme.colors.alertError : Theme.colors.textPrimary,
                    lineWidth: 1.5
                )
            }
            .scaleEffect(isFilled ? 1 : 0.82)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isFilled)
    }

    private var biometricButton: some View {
        Button(action: startBiometricUnlock) {
            HStack(spacing: 8) {
                Image("passcode-face-id")
                    .resizable()
                    .frame(width: 20, height: 20)

                Text("passcodeUseFaceID".localized)
                    .font(Theme.fonts.buttonSMedium)
                    .foregroundStyle(Theme.colors.alertInfo)
                    .frame(height: 18)
            }
            .frame(height: 20)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !isBiometricUnlockAvailable)
        .opacity(isBiometricUnlockAvailable ? 1 : 0)
        .accessibilityHidden(!isBiometricUnlockAvailable)
        .accessibilityIdentifier(AccessibilityID.Passcode.useBiometricsButton)
    }

    private func startBiometricUnlock() {
        #if os(iOS)
        isPasscodeFieldFocused = false
        #endif
        onBiometricUnlock()
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
private extension LockPasscodeEntryView {
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
            .task(id: isBusy) { @MainActor in
                if isBusy {
                    isPasscodeFieldFocused = false
                    return
                }

                // Re-focusing while the previous keyboard dismissal is still
                // animating is ignored. This task is cancelled if busy changes
                // again or the lock screen leaves the hierarchy.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
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

private struct LockScreenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.colors.bgPrimary

            EllipticalGradient(
                colors: [
                    Theme.colors.primaryAccent2.opacity(0.9),
                    Theme.colors.bgPrimary.opacity(0)
                ],
                center: .top
            )
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .offset(y: -80)
            .blur(radius: 30)
        }
    }
}

#if os(macOS)
private struct LockPasscodeKeypad: View {
    private struct Key: Identifiable {
        let id: String
        let digit: String?
        let letters: String?

        static func digit(_ digit: String, letters: String? = nil) -> Self {
            Self(id: digit, digit: digit, letters: letters)
        }

        static let blank = Self(id: "blank", digit: nil, letters: nil)
        static let delete = Self(id: "delete", digit: nil, letters: nil)
    }

    private static let keys: [Key] = [
        .digit("1"), .digit("2", letters: "A B C"), .digit("3", letters: "D E F"),
        .digit("4", letters: "G H I"), .digit("5", letters: "J K L"), .digit("6", letters: "M N O"),
        .digit("7", letters: "P Q R S"), .digit("8", letters: "T U V"), .digit("9", letters: "W X Y Z"),
        .blank, .digit("0"), .delete
    ]

    let isBusy: Bool
    let actions: PasscodeInputActions

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
            spacing: 6
        ) {
            ForEach(Self.keys) { key in
                keyView(key)
                    .frame(height: 46)
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 25)
        .frame(maxWidth: 393, maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.lockKeypadBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.radius.xl.points,
                topTrailingRadius: Theme.radius.xl.points
            )
        )
        .disabled(isBusy)
        .opacity(isBusy ? 0.65 : 1)
        .animation(.easeInOut(duration: 0.15), value: isBusy)
    }

    @ViewBuilder
    private func keyView(_ key: Key) -> some View {
        if let digit = key.digit {
            Button {
                actions.append(digit)
            } label: {
                VStack(spacing: -2) {
                    Text(digit)
                        .font(Theme.fonts.lockKeypadDigit)

                    if let letters = key.letters {
                        Text(letters)
                            .font(Theme.fonts.lockKeypadLetters)
                    }
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(LockPasscodeKeyStyle(hasFill: true))
            .accessibilityIdentifier(AccessibilityID.Passcode.digitKey(digit))
        } else if key.id == "delete" {
            Button(action: actions.deleteLast) {
                Image(systemName: "delete.left")
                    .font(Theme.fonts.keypadGlyph)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(LockPasscodeKeyStyle(hasFill: false))
            .accessibilityIdentifier(AccessibilityID.Passcode.deleteKey)
            .accessibilityLabel("delete".localized)
        } else {
            Color.clear
        }
    }
}

private struct LockPasscodeKeyStyle: ButtonStyle {
    let hasFill: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if hasFill {
                    Theme.radius.sm.shape
                        .fill(Theme.colors.lockKeypadKey)
                }
            }
            .overlay {
                if configuration.isPressed {
                    Theme.radius.sm.shape
                        .fill(Color.white.opacity(0.2))
                }
            }
            .clipShape(Theme.radius.sm.shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif

private struct LockShakeEffect: GeometryEffect {
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
