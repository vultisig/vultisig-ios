//
//  StepIndicatorView.swift
//  VultisigApp
//

import SwiftUI

/// A row of step icons joined by hairline connectors. Each icon shows the
/// state `state(index)` returns and is tappable while `canSelect(index)`.
struct StepIndicatorView: View {
    let icons: [ImageResource]
    /// VoiceOver label per step, in icon order. Steps without one keep the
    /// icon's default label.
    var labels: [String] = []
    /// Fades state colour changes and pops an icon when its step turns valid.
    var animatesStateChanges = false
    var iconSize: VaultSetupStepIcon.Size = .regular
    let state: (Int) -> VaultSetupStepState
    let canSelect: (Int) -> Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                if index > 0 {
                    connector
                }
                Button {
                    onSelect(index)
                } label: {
                    stepIcon(icon, state: state(index))
                }
                .buttonStyle(.plain)
                .disabled(!canSelect(index))
                .if(labels.indices.contains(index)) {
                    $0.accessibilityLabel(labels[index])
                }
            }
        }
    }

    private var connector: some View {
        // Off the radius scale on purpose: a 1pt hairline renders fully round at any radius.
        RoundedRectangle(cornerRadius: 1) // swiftlint:disable:this no_raw_corner_radius
            .fill(Theme.colors.border)
            .frame(width: 16, height: 1)
    }

    @ViewBuilder
    private func stepIcon(_ icon: ImageResource, state: VaultSetupStepState) -> some View {
        if animatesStateChanges {
            AnimatedStepIcon(state: state, icon: icon, size: iconSize)
        } else {
            VaultSetupStepIcon(state: state, icon: icon, size: iconSize)
        }
    }
}

private struct AnimatedStepIcon: View {
    let state: VaultSetupStepState
    let icon: ImageResource
    let size: VaultSetupStepIcon.Size

    @State private var validPops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VaultSetupStepIcon(state: state, icon: icon, size: size)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state)
            .keyframeAnimator(initialValue: 1.0, trigger: validPops) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.08, duration: 0.15)
                SpringKeyframe(1.0, duration: 0.2)
            }
            .onChange(of: state) { _, newState in
                guard newState == .valid, !reduceMotion else { return }
                validPops += 1
            }
    }
}
