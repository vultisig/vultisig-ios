//
//  LimitHoldStepButton.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Press-and-hold stepper button
//
// A tap emits exactly one step; holding keeps emitting, with the STEP widening
// the longer it is held (`limitPctStep(forHeldSeconds:)`). Accelerating the step
// rather than the tick rate is what makes the far end of the range reachable: at
// a flat tenth per tick, the +20% where the far-above-market warning begins is two
// hundred ticks away, and a tick rate fast enough to fix that would make a short
// hold impossible to land on a value.

struct LimitHoldStepButton: View {

    let systemImage: String
    let accessibilityLabelKey: String
    let isEnabled: Bool
    /// Applies one step of the given size, and reports whether the value actually
    /// MOVED. The return value is what stops a held repeat at the range bound: a
    /// press pinned against the clamp would otherwise keep waking every 80ms
    /// applying no-ops for as long as the finger stayed down.
    let onStep: (Decimal) -> Bool

    /// Long enough that a deliberate single tap never trips the repeat, short
    /// enough that a hold doesn't feel stuck before it starts moving.
    private static let repeatDelaySeconds = 0.4
    private static let repeatIntervalSeconds = 0.08

    /// `@GestureState` rather than `@State`, and this is the load-bearing choice:
    /// SwiftUI resets it to `false` when the gesture ends *or is cancelled*, so a
    /// press interrupted by a call, a notification, or a competing recogniser
    /// still stops the repeat. Ending on `DragGesture.onEnded` alone does not —
    /// a cancelled gesture never delivers it, and a `+` left running would keep
    /// walking the price with nobody touching the screen.
    @GestureState private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isEnabled ? Theme.colors.textPrimary : Theme.colors.textTertiary)
            .frame(width: 44, height: 44)
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
            .accessibilityLabel(accessibilityLabelKey.localized)
            .accessibilityAddTraits(.isButton)
            // A raw gesture carries no activation for VoiceOver, which drives
            // controls by action and not by touch. One step per activation is the
            // honest equivalent of a tap; press-and-hold stays for everyone else.
            .accessibilityAction {
                guard isEnabled else { return }
                _ = onStep(limitPctStep(forHeldSeconds: 0))
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
        guard onStep(limitPctStep(forHeldSeconds: 0)) else { return }
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.repeatDelaySeconds))
            // Elapsed is accumulated rather than clock-read so the step schedule
            // is a pure function of how many ticks have fired.
            var heldSeconds = Self.repeatDelaySeconds
            while !Task.isCancelled {
                guard onStep(limitPctStep(forHeldSeconds: heldSeconds)) else { return }
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
