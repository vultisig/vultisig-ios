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
    @State private var shouldRestorePasscodeFieldFocus = false
    #endif

    private var digitCount: Int { PasscodeService.passcodeLength }
    private var hasError: Bool { errorMessage?.isEmpty == false }

    var body: some View {
        ZStack {
            PasscodeBackground()
                .ignoresSafeArea()

            PasscodeInput(
                passcode: $passcode,
                isBusy: isBusy,
                onComplete: onComplete
            ) { _ in
                #if os(iOS)
                lockContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 26)
                    .overlay(alignment: .topLeading) {
                        nativePasscodeField
                    }
                #else
                lockContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                biometricIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                Text(biometricTitle)
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

    private var biometricIcon: Image {
        #if os(iOS)
        Image("passcode-face-id")
        #else
        Image(systemName: "touchid")
        #endif
    }

    private var biometricTitle: String {
        #if os(iOS)
        "passcodeUseFaceID".localized
        #else
        "passcodeUseTouchID".localized
        #endif
    }

    private func startBiometricUnlock() {
        #if os(iOS)
        shouldRestorePasscodeFieldFocus = true
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
                guard !isBusy else { return }

                if shouldRestorePasscodeFieldFocus {
                    // Re-focusing while the biometric sheet is still dismissing
                    // is ignored. This task is cancelled if busy changes again
                    // or the lock screen leaves the hierarchy.
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    shouldRestorePasscodeFieldFocus = false
                }
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
