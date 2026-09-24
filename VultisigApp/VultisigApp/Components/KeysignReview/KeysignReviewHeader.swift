//
//  KeysignReviewHeader.swift
//  VultisigApp
//

import SwiftUI
import RiveRuntime

/// Maps the scan result to the Blockaid animation and its VoiceOver label.
struct KeysignReviewScanRing: Equatable {
    enum Tone: Equatable {
        case safe
        case warning
        case danger
    }

    enum AnimationState: Equatable {
        case hidden
        case loading
        case success
        case mediumRisk
        case highRisk

        var triggerName: String? {
            switch self {
            case .success: "success"
            case .mediumRisk: "mediumRisk"
            case .highRisk: "highRisk"
            case .hidden, .loading: nil
            }
        }

        var isTerminal: Bool { triggerName != nil }
    }

    let tone: Tone?
    let animationState: AnimationState
    let accessibilityLabel: String?

    static let hidden = KeysignReviewScanRing(tone: nil, animationState: .hidden, accessibilityLabel: nil)

    private init(tone: Tone?, animationState: AnimationState, accessibilityLabel: String?) {
        self.tone = tone
        self.animationState = animationState
        self.accessibilityLabel = accessibilityLabel
    }

    init(_ state: SecurityScannerState, isScanComplete: Bool = false) {
        switch state {
        case .notScanned:
            self = .hidden
            return
        case .idle:
            // Start with the sheet, including fee preparation. An unavailable
            // scan returns idle, so completion must stop the loading artwork.
            self = isScanComplete ? .hidden : Self(.scanning)
            return
        case .scanning:
            self.init(tone: nil, animationState: .loading, accessibilityLabel: "securityScannerTransactionScanning".localized)
            return
        case .scanned(let result):
            if result.isSecure {
                self.init(
                    tone: .safe,
                    animationState: .success,
                    accessibilityLabel: "\("securityScannerTransactionScannedBy".localized) \(result.provider.capitalized)"
                )
                return
            }
            switch result.riskLevel {
            case .high:
                self.init(tone: .danger, animationState: .highRisk, accessibilityLabel: "securityScannerHighRiskTitle".localized)
            case .critical:
                self.init(tone: .danger, animationState: .highRisk, accessibilityLabel: "securityScannerCriticalRiskTitle".localized)
            case .medium:
                self.init(tone: .warning, animationState: .mediumRisk, accessibilityLabel: "securityScannerMediumRiskTitle".localized)
            case .noRisk, .low:
                self.init(tone: .warning, animationState: .mediumRisk, accessibilityLabel: "securityScannerLowRiskTitle".localized)
            }
        }
    }
}

/// Owns one Rive instance per scan. Recreating it resets the state machine to
/// Loading when a scan is retried or another outcome is tested.
private struct KeysignReviewScanMark: View {
    let scanRing: KeysignReviewScanRing

    @State private var animationVM: RiveViewModel?
    @State private var animationInstance: RiveDataBindingViewModel.Instance?
    @State private var activeState: KeysignReviewScanRing.AnimationState = .hidden
    @State private var firedState: KeysignReviewScanRing.AnimationState?
    @State private var generation = 0

    var body: some View {
        ZStack {
            if scanRing.animationState != .hidden {
                Circle().fill(Theme.colors.bgSheetControl)

                animationVM?.view()
                    // Rive's representable updates layout only; a new model
                    // needs a new native view to render the reset state machine.
                    .id(generation)
                    .frame(width: KeysignReviewSheetLayout.controlSize, height: KeysignReviewSheetLayout.controlSize)
            }
        }
        .frame(width: KeysignReviewSheetLayout.controlSize, height: KeysignReviewSheetLayout.controlSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scanRing.accessibilityLabel ?? "")
        .accessibilityHidden(scanRing.accessibilityLabel == nil)
        .onAppear { transition(to: scanRing.animationState) }
        .onChange(of: scanRing.animationState) { _, state in transition(to: state) }
        .onDisappear { clearAnimation() }
    }

    private func transition(to state: KeysignReviewScanRing.AnimationState) {
        let previousState = activeState
        activeState = state

        if state == .hidden {
            clearAnimation()
        } else if state == .loading || animationVM == nil || (previousState.isTerminal && previousState != state) {
            resetAnimation()
        } else {
            fireOutcomeIfNeeded()
        }
    }

    private func resetAnimation() {
        clearAnimation()
        let currentGeneration = generation

        let vm = RiveViewModel(fileName: "blockaid_scan", stateMachineName: "State Machine 1", autoPlay: true)
        vm.riveModel?.enableAutoBind { instance in
            Task { @MainActor in
                guard generation == currentGeneration else { return }
                animationInstance = instance
                firedState = nil
                fireOutcomeIfNeeded()
            }
        }
        animationVM = vm
    }

    private func fireOutcomeIfNeeded() {
        guard firedState != activeState,
              let triggerName = activeState.triggerName,
              let trigger = animationInstance?.triggerProperty(fromPath: triggerName) else { return }
        trigger.trigger()
        // Data-binding triggers do not resume a settled state machine.
        animationVM?.play()
        firedState = activeState
    }

    private func clearAnimation() {
        generation += 1
        animationVM?.riveModel?.disableAutoBind()
        animationVM?.stop()
        animationVM = nil
        animationInstance = nil
        firedState = nil
    }
}

struct KeysignReviewHeader<Accessory: View>: View {
    let title: String
    let scanRing: KeysignReviewScanRing
    let onClose: () -> Void
    /// Shown just before the close button.
    let accessory: () -> Accessory

    @State private var trailingWidth: CGFloat = KeysignReviewSheetLayout.controlSize

    var body: some View {
        HStack(spacing: 0) {
            scanMark
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                accessory()
                closeButton
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailingWidth = $0 }
        }
        .frame(height: KeysignReviewSheetLayout.controlSize)
        .overlay {
            // Centred on the sheet, so it keeps clear of the wider side.
            Text(title)
                .keysignReviewText(.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, max(KeysignReviewSheetLayout.controlSize, trailingWidth) + 8)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var scanMark: some View {
        KeysignReviewScanMark(scanRing: scanRing)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(width: KeysignReviewSheetLayout.controlSize, height: KeysignReviewSheetLayout.controlSize)
                .background(Circle().fill(Theme.colors.bgSheetControl))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close".localized)
    }
}
