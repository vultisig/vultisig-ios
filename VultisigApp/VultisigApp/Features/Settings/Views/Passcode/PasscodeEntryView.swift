//
//  PasscodeEntryView.swift
//  VultisigApp
//

import SwiftUI

/// Fixed-length entry: filled dots over a keypad, on both platforms. The number
/// of dots comes from ``PasscodeService/passcodeLength``, so nothing here has the
/// length written into it.
///
/// One component for every flow — lock screen, set, confirm, change, disable — so
/// entering a passcode looks and behaves the same everywhere it is asked for.
///
/// macOS shows the same keypad rather than a text field. A passcode is six digits
/// on a numeric pad, and rendering it as a bordered `SecureField` made it look
/// like a password box on one platform and a passcode on the other. The hardware
/// keyboard still types into it — see ``handleKeyPress(_:)`` — so the pad is an
/// addition on the Mac, not a replacement for the keys under the user's hands.
struct PasscodeEntryView: View {

    let title: String
    let subtitle: String?
    var errorMessage: String?
    var isBusy: Bool = false
    /// Shown on the lock screen only. The settings flows are already inside a
    /// titled, branded navigation stack, so a logo there is noise.
    var showsLogo: Bool = false
    @Binding var passcode: String
    /// Called once the last digit lands, so no flow needs its own submit button.
    let onComplete: (String) -> Void

    /// Bumped on each error to drive the shake; the value itself is meaningless.
    @State private var shakeTravel: CGFloat = 0
    #if os(macOS)
    /// Held by the keypad so hardware key presses reach it. Clicking a key takes
    /// focus away to the button, so it is taken back on every entry rather than
    /// only on appearance — otherwise one click ends typing for the rest of the
    /// flow.
    @FocusState private var isKeypadFocused: Bool
    #endif

    private var digitCount: Int { PasscodeService.passcodeLength }
    private var hasError: Bool { errorMessage?.isEmpty == false }

    var body: some View {
        VStack(spacing: 0) {
            if showsLogo {
                Image("vultisig-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64)
                    .padding(.bottom, 20)
            }

            header
                .padding(.top, 8)

            dots
                .padding(.top, 32)

            message
                .padding(.top, 16)

            // Balanced spacers rather than one at the top: the keypad sits in
            // the middle of the space below the dots instead of being pinned to
            // the bottom edge, which left a large dead gap on tall screens.
            Spacer(minLength: 12)

            keypad

            Spacer(minLength: 8)

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
        #if os(macOS)
        // Focused rather than merely focusable: whoever opened this screen came
        // here to type six digits, and a first keystroke that goes nowhere
        // because nothing claimed focus reads as a screen that is not listening.
        // The focus ring is suppressed because the dots already show where the
        // input is going.
        .focusable()
        .focusEffectDisabled()
        .focused($isKeypadFocused)
        .onAppear { isKeypadFocused = true }
        .onKeyPress(phases: .down) { handleKeyPress($0) }
        #endif
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
        #else
        isKeypadFocused = true
        #endif
    }

    private func deleteLast() {
        guard !passcode.isEmpty, !isBusy else { return }
        passcode.removeLast()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #else
        isKeypadFocused = true
        #endif
    }

    #if os(macOS)
    /// Routes a hardware key to the same two operations the on-screen keys call,
    /// so typing and clicking cannot diverge.
    ///
    /// ASCII digits only, which is what ``PasscodeService/validate(_:)`` accepts
    /// and what the pad can produce. A keyboard laid out for Arabic-Indic digits
    /// would otherwise enter a passcode that could never be typed on the phone
    /// this vault is also on.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .delete || press.key == .deleteForward {
            deleteLast()
            return .handled
        }

        guard press.characters.count == 1,
              let digit = press.characters.first,
              digit.isASCII, digit.isNumber else {
            return .ignored
        }

        append(String(digit))
        return .handled
    }
    #endif
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
                    .font(Theme.fonts.keypadGlyph)
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
                    .font(Theme.fonts.keypadDigit)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(width: keyDiameter, height: keyDiameter)
                    .contentShape(Circle())
            }
            .buttonStyle(PasscodeKeyButtonStyle(hasFill: true))
            .accessibilityIdentifier(AccessibilityID.Passcode.digitKey(key))
        }
    }
}

/// Circular glass key.
///
/// Uses the same treatment as `ToolbarButton` / `VultiTabBar` — `.glassEffect`
/// on iOS 26, with their gradient-stroke fallback below it — rather than
/// `.ultraThinMaterial`, which renders as flat opaque grey over a dark
/// background and loses the translucency entirely. macOS takes the same
/// fallback: `glassEffect` is iOS-only, and the stroke is what carries the shape
/// there.
private struct PasscodeKeyButtonStyle: ButtonStyle {
    let hasFill: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { fill }
            .overlay {
                if configuration.isPressed {
                    Circle().fill(Theme.colors.textPrimary.opacity(0.22))
                }
            }
            .clipShape(Circle())
            // Press compresses hard and fast; release overshoots slightly before
            // settling. A single symmetric spring reads as mushy next to the
            // platform keypad, which snaps down and bounces back.
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.12, dampingFraction: 0.55)
                    : .spring(response: 0.34, dampingFraction: 0.42),
                value: configuration.isPressed
            )
    }

    @ViewBuilder
    private var fill: some View {
        if hasFill {
            #if os(iOS)
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(.clear.interactive(), in: Circle())
            } else {
                strokedFill
            }
            #else
            strokedFill
            #endif
        }
    }

    private var strokedFill: some View {
        Circle()
            .fill(Theme.colors.bgSurface1.opacity(0.35))
            .overlay(
                Circle().stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .clear, .clear, .white.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
    }
}
