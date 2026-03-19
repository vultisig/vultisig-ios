//
//  LongPressPrimaryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/07/2025.
//

import SwiftUI

struct LongPressPrimaryButton: View {
    @State private var progress: CGFloat = 0.0
    @State private var isPressed = false
    @State private var longPressTask: Task<Void, Never>?

    let title: String
    let action: () -> Void
    let longPressAction: () -> Void

    let longPressDuration: Double = 1.5

    var body: some View {
        PrimaryButton(
            title: title,
            supportsLongPress: true,
            longPressProgress: $progress
        ) {}
            .onLongPressGesture(
                minimumDuration: 0,
                maximumDistance: 0,
                perform: {},
                onPressingChanged: { pressing in
                    if pressing {
                        startHold()
                    } else {
                        stopHold()
                    }
            })
            .simultaneousGesture(TapGesture().onEnded { _ in
                if !isPressed {
                    action()
                }
            })
    }
}

private extension LongPressPrimaryButton {
    func startHold() {
        guard !isPressed else { return }

        longPressTask = Task { @MainActor in
            // Small delay to prevent tap gesture conflicts
            try? await Task.sleep(for: .milliseconds(100))

            guard !Task.isCancelled else { return }

            #if os(iOS)
                HapticFeedbackManager.shared.startHapticFeedback(duration: longPressDuration, interval: 0.15)
            #endif

            isPressed = true
            withAnimation(.easeIn(duration: longPressDuration)) {
                progress = 1.0
            }

            // Wait for the long press duration
            try? await Task.sleep(for: .seconds(longPressDuration))

            guard !Task.isCancelled else {
                return
            }

            onLongPressComplete()
        }
    }

    func stopHold() {
        isPressed = false

        // Cancel the long press task
        longPressTask?.cancel()
        longPressTask = nil

        #if os(iOS)
            HapticFeedbackManager.shared.stopHapticFeedback()
        #endif
        withAnimation(.easeOut(duration: 0.3)) {
            progress = 0.0
        }
    }

    func onLongPressComplete() {
        #if os(iOS)
            HapticFeedbackManager.shared.stopHapticFeedback()
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        #endif

        // Delay for smoother transition
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            stopHold()
            longPressAction()
        }
    }

}
