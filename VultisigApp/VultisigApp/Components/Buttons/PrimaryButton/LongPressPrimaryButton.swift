//
//  LongPressPrimaryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/07/2025.
//

import SwiftUI

struct LongPressPrimaryButton: View {
    @State private var pressStart: Date?
    @State private var didFireLongPress = false
    @State private var holdTask: Task<Void, Never>?
    @State private var outroProgress: CGFloat = 0

    let title: String
    let action: () -> Void
    let longPressAction: () -> Void

    private let tapThreshold: Double = 0.1
    private let longPressDuration: Double = 1.5

    var body: some View {
        TimelineView(.animation(paused: timelinePaused)) { context in
            PrimaryButton(
                title: title,
                supportsLongPress: true,
                longPressProgress: .constant(progress(at: context.date)),
                action: {}
            )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in handlePressDown() }
                .onEnded { _ in handleRelease() }
        )
        .onAppear { resetState() }
    }
}

private extension LongPressPrimaryButton {
    var holdDuration: Double { longPressDuration - tapThreshold }

    var timelinePaused: Bool { pressStart == nil || didFireLongPress }

    func progress(at now: Date) -> CGFloat {
        guard let start = pressStart, !didFireLongPress else { return outroProgress }
        let elapsed = now.timeIntervalSince(start) - tapThreshold
        guard elapsed > 0 else { return 0 }
        return min(CGFloat(elapsed / holdDuration), 1)
    }

    func handlePressDown() {
        guard pressStart == nil else { return }
        outroProgress = 0
        didFireLongPress = false
        pressStart = Date()
        startHoldTimer()
    }

    func handleRelease() {
        guard let start = pressStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        let wasLongPress = didFireLongPress

        finalizeGesture()

        guard !wasLongPress else { return }
        if elapsed < tapThreshold {
            action()
        }
    }

    func startHoldTimer() {
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(tapThreshold))
            guard !Task.isCancelled else { return }

            #if os(iOS)
                HapticFeedbackManager.shared.startHapticFeedback(duration: holdDuration, interval: 0.15)
            #endif

            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled else { return }

            // Long press completed. Leave `pressStart` set — the finger is still
            // down, and clearing it would let the next DragGesture jitter event
            // start a fresh press cycle that fires `action()` on lift.
            didFireLongPress = true
            outroProgress = 1.0

            #if os(iOS)
                HapticFeedbackManager.shared.stopHapticFeedback()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            #endif

            startOutroFade()
            longPressAction()
        }
    }

    // Cancel path (release before 1.5s) and the no-op release after a long press.
    func finalizeGesture() {
        // Snapshot for the cancel-path outro. After a long press, `outroProgress`
        // is already animating from 1.0 — leave it alone.
        if !didFireLongPress, let start = pressStart {
            let elapsed = Date().timeIntervalSince(start) - tapThreshold
            outroProgress = elapsed > 0 ? min(CGFloat(elapsed / holdDuration), 1) : 0
        }

        pressStart = nil
        holdTask?.cancel()
        holdTask = nil

        #if os(iOS)
            HapticFeedbackManager.shared.stopHapticFeedback()
        #endif

        if !didFireLongPress {
            startOutroFade()
        }
    }

    func startOutroFade() {
        // Defer one render cycle so SwiftUI commits the snapshot before the easeOut.
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                outroProgress = 0.0
            }
        }
    }

    func resetState() {
        pressStart = nil
        didFireLongPress = false
        holdTask?.cancel()
        holdTask = nil
        outroProgress = 0

        #if os(iOS)
            HapticFeedbackManager.shared.stopHapticFeedback()
        #endif
    }
}
