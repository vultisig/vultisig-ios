//
//  LimitHoldStepButton.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Press-and-hold stepper button
//
// A tap emits exactly one step; holding keeps emitting until the value stops
// moving or the finger lifts.
//
// The button owns the TIMING and nothing else — it hands the caller how long the
// press has been held and lets the caller decide what one step is worth at that
// point. Its two users want opposite things from a hold and both are right: the
// percent offset spans hundreds of steps, so its step widens the longer it is
// held (`limitPctStep(forHeldSeconds:)`) or the +20% where the far-above-market
// warning begins would be two hundred ticks away; the expiry steppers span 12 to
// 24 steps end to end, so a constant step crosses them in about a second and
// accelerating would make them impossible to land on. Baking either schedule in
// here would have forced the other one to be wrong.

struct LimitHoldStepButton: View {

    let systemImage: String
    /// Already localized — callers format it (the expiry steppers name their unit).
    let accessibilityLabel: String
    let isEnabled: Bool
    /// Diameter of the tappable circle. Defaults to the 44pt hit target; the
    /// expiry sheet packs three steppers into one row and passes a smaller one.
    var diameter: CGFloat = 44
    var glyphPointSize: CGFloat = 16
    /// Applies one step for a press held `heldSeconds`, and reports whether the
    /// value actually MOVED. The return value is what stops a held repeat at the
    /// range bound: a press pinned against the clamp would otherwise keep waking
    /// every 80ms applying no-ops for as long as the finger stayed down.
    let onStep: (Double) -> Bool

    /// Long enough that a deliberate single tap never trips the repeat, short
    /// enough that a hold doesn't feel stuck before it starts moving.
    private static let repeatDelaySeconds = 0.4
    private static let repeatIntervalSeconds = 0.08

    /// `@GestureState` rather than `@State`, and this is the load-bearing choice:
    /// SwiftUI resets it to `false` when the gesture ends *or is cancelled*, so a
    /// press interrupted by a call, a notification, or a competing recogniser
    /// still stops the repeat. Ending on `DragGesture.onEnded` alone does not —
    /// a cancelled gesture never delivers it, and a `+` left running would keep
    /// walking the value with nobody touching the screen.
    @GestureState private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: glyphPointSize, weight: .semibold))
            .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textTertiary)
            .frame(width: diameter, height: diameter)
            .background(Theme.colors.bgSurface2)
            .clipShape(Circle())
            .opacity(isPressing ? 0.6 : 1)
            .contentShape(Circle())
            // High priority so a press that begins on the button is the button's:
            // inside a sheet, a plain gesture competes with the interactive
            // dismiss, and a hold that drifts downward would pull the sheet away
            // mid-adjustment.
            .highPriorityGesture(pressGesture)
            .onChange(of: isPressing) { _, pressing in
                if pressing {
                    beginPress()
                } else {
                    endPress()
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            // A raw gesture carries no activation for VoiceOver, which drives
            // controls by action and not by touch. One step per activation is the
            // honest equivalent of a tap; press-and-hold stays for everyone else.
            .accessibilityAction {
                guard isEnabled else { return }
                _ = onStep(0)
            }
            // Carries the state to assistive tech, which a dimmed glyph alone does
            // not: at a clamp this is the difference between VoiceOver offering a
            // button that does nothing and announcing it as dimmed. It also blocks
            // the gesture, so the guards below it are belt-and-braces rather than
            // the only defence.
            .disabled(!isEnabled)
            .onDisappear(perform: endPress)
    }

    /// A zero-distance drag rather than a `Button`: the press has to be observable
    /// at touch-DOWN, which is where the first step is emitted and where the
    /// repeat timer starts. A `Button` only reports the completed tap, so a hold
    /// would move nothing until the finger came up.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressing) { _, pressing, _ in pressing = true }
    }

    private func beginPress() {
        guard isEnabled else { return }
        repeatTask?.cancel()
        guard onStep(0) else { return }
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.repeatDelaySeconds))
            // Elapsed is accumulated rather than clock-read so the step schedule
            // is a pure function of how many ticks have fired.
            var heldSeconds = Self.repeatDelaySeconds
            while !Task.isCancelled {
                guard onStep(heldSeconds) else { return }
                try? await Task.sleep(for: .seconds(Self.repeatIntervalSeconds))
                heldSeconds += Self.repeatIntervalSeconds
            }
        }
    }

    private func endPress() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
