//
//  PasscodeEntryView.swift
//  VultisigApp
//

import SwiftUI

/// Five-digit entry: filled dots plus a keypad on iOS, hardware keyboard on macOS.
///
/// One component for every flow — lock screen, set, confirm, change, disable — so
/// entering a passcode looks and behaves the same everywhere it is asked for.
struct PasscodeEntryView: View {

    let title: String
    let subtitle: String?
    var errorMessage: String?
    var isBusy: Bool = false
    @Binding var passcode: String
    /// Called once the last digit lands, so no flow needs its own submit button.
    let onComplete: (String) -> Void

    /// Bumped on each error to drive the shake; the value itself is meaningless.
    @State private var shakeTravel: CGFloat = 0
    #if os(macOS)
    @FocusState private var isFieldFocused: Bool
    #endif

    private var digitCount: Int { PasscodeService.passcodeLength }
    private var hasError: Bool { errorMessage?.isEmpty == false }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)

            dots
                .padding(.top, 32)

            message
                .padding(.top, 16)

            Spacer(minLength: 24)

            keypad
        }
        .frame(maxWidth: .infinity)
        .onChange(of: passcode) { _, value in
            guard value.count == digitCount else { return }
            onComplete(value)
        }
        .onChange(of: errorMessage) { _, message in
            guard message?.isEmpty == false else { return }
            reactToError()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
                .id(title)
                .transition(.opacity.combined(with: .move(edge: .top)))

            if let subtitle {
                Text(subtitle)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .id(subtitle)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        // Stage changes (choose → confirm, current → new) cross-fade rather than
        // snapping, so the step the user is on stays legible.
        .animation(.easeInOut(duration: 0.28), value: title)
        .animation(.easeInOut(duration: 0.28), value: subtitle)
    }

    private var dots: some View {
        HStack(spacing: 20) {
            ForEach(0..<digitCount, id: \.self) { index in
                let isFilled = index < passcode.count
                Circle()
                    .fill(isFilled ? Theme.colors.textPrimary : Color.clear)
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle().stroke(
                            hasError ? Theme.colors.alertError : Theme.colors.textPrimary.opacity(0.4),
                            lineWidth: 1.5
                        )
                    )
                    // A filled dot pops in rather than appearing, so the count
                    // reads peripherally while the eyes are on the keypad.
                    .scaleEffect(isFilled ? 1 : 0.82)
                    .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isFilled)
            }
        }
        .modifier(ShakeEffect(travel: shakeTravel))
        .animation(.easeInOut(duration: 0.2), value: hasError)
        .accessibilityIdentifier(AccessibilityID.Passcode.dots)
        .accessibilityValue("\(passcode.count)")
    }

    private var message: some View {
        // Height is reserved either way, so the dots and keypad do not shift when
        // an error appears or clears.
        Text(errorMessage ?? " ")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.alertError)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .opacity(hasError ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    /// Shakes the dots and fires an error haptic.
    ///
    /// A wrong entry is the one moment the user has to notice without reading, so
    /// it is felt as well as seen — and the dots are what shake, because they are
    /// what was wrong.
    private func reactToError() {
        withAnimation(.linear(duration: 0.4)) {
            shakeTravel += 1
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    private func append(_ digit: String) {
        guard passcode.count < digitCount, !isBusy else { return }
        passcode.append(digit)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func deleteLast() {
        guard !passcode.isEmpty, !isBusy else { return }
        passcode.removeLast()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Horizontal shake driven by one animatable value, so the whole wiggle is a
/// single animation rather than a chain of nested completion handlers.
private struct ShakeEffect: GeometryEffect {
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

#if os(iOS)
extension PasscodeEntryView {

    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    private var keyDiameter: CGFloat { 74 }

    /// One `LazyVGrid` rather than four stacked `HStack`s.
    ///
    /// The previous layout built each row separately and used `Color.clear` as
    /// the blank key. `Color` expands greedily in both axes, so the blank grew
    /// vertically and shoved the last row far below the other three. A single
    /// grid with uniform spacing cannot fall out of alignment that way.
    var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(keyDiameter), spacing: 28), count: 3),
            spacing: 18
        ) {
            ForEach(Self.keys, id: \.self) { key in
                keyView(for: key)
            }
        }
        .padding(.bottom, 16)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.15), value: isBusy)
    }

    @ViewBuilder
    private func keyView(for key: String) -> some View {
        switch key {
        case "":
            // Fixed size, not a greedy `Color`.
            Color.clear.frame(width: keyDiameter, height: keyDiameter)
        case "⌫":
            Button(action: deleteLast) {
                Image(systemName: "delete.left")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(width: keyDiameter, height: keyDiameter)
                    .contentShape(Circle())
            }
            .buttonStyle(PasscodeKeyButtonStyle(hasFill: false))
            .accessibilityIdentifier(AccessibilityID.Passcode.deleteKey)
            .accessibilityLabel("delete".localized)
        default:
            Button {
                append(key)
            } label: {
                Text(key)
                    .font(.system(size: 32, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(width: keyDiameter, height: keyDiameter)
                    .contentShape(Circle())
            }
            .buttonStyle(PasscodeKeyButtonStyle(hasFill: true))
            .accessibilityIdentifier(AccessibilityID.Passcode.digitKey(key))
        }
    }
}

/// Circular translucent key with a press state, matching the platform passcode
/// affordance rather than the app's rectangular buttons. A keypad should read as
/// a keypad — users already know how this one behaves.
private struct PasscodeKeyButtonStyle: ButtonStyle {
    let hasFill: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if hasFill {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Theme.colors.borderLight.opacity(0.7), lineWidth: 1))
                }
            }
            .overlay {
                if configuration.isPressed {
                    Circle().fill(Theme.colors.textPrimary.opacity(0.18))
                }
            }
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
#endif

#if os(macOS)
extension PasscodeEntryView {

    /// No on-screen keypad on macOS — the hardware keyboard drives entry and the
    /// dots above render the state.
    ///
    /// The field is visible and focused on appearance rather than hidden at one
    /// pixel: an invisible field gives the user nothing to click when focus is
    /// lost, which makes entry unreliable and occasionally impossible.
    var keypad: some View {
        SecureField("passcodeEnterTitle".localized, text: Binding(
            get: { passcode },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                passcode = String(digits.prefix(PasscodeService.passcodeLength))
            }
        ))
        .textFieldStyle(.roundedBorder)
        .font(Theme.fonts.bodyMMedium)
        .frame(maxWidth: 220)
        .padding(.bottom, 24)
        .focused($isFieldFocused)
        .disabled(isBusy)
        .onAppear { isFieldFocused = true }
        .accessibilityIdentifier(AccessibilityID.Passcode.macField)
    }
}
#endif
