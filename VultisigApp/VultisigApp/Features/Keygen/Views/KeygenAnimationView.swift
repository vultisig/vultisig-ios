//
//  KeygenAnimationView.swift
//  VultisigApp
//

import SwiftUI
import RiveRuntime

struct KeygenAnimationView: View {

    var isFast: Bool = true
    @Binding var connected: Bool
    @Binding var progress: Float

    private var fileName: String {
        isFast ? "keygen_fast" : "keygen_secure"
    }

    @State private var animationVM: RiveViewModel?
    @State private var animationVMInstance: RiveDataBindingViewModel.Instance?
    @State private var displayedProgress: Float = 0
    @State private var progressAnimationTimer: Timer?

    var body: some View {
        ZStack {
            animationVM?.view()
        }
        .ignoresSafeArea()
        .readSize { size in
            let posXcircles = animationVMInstance?.numberProperty(fromPath: "posXcircles")
            posXcircles?.value = Float(size.width / 2)
        }
        .onChange(of: progress) { _, newValue in
            animateProgress(to: newValue)
        }
        .onChange(of: connected) { _, newValue in
            let connectedProperty = animationVMInstance?.booleanProperty(fromPath: "Connected")
            connectedProperty?.value = newValue
        }
        .onAppear {
            setupAnimation()
#if os(iOS)
            HapticFeedbackManager.shared.playAHAPFile(named: "keygen_animation_haptic", looping: true)
#endif
        }
        .onDisappear {
            animationVM?.stop()
            progressAnimationTimer?.invalidate()
            progressAnimationTimer = nil
#if os(iOS)
            HapticFeedbackManager.shared.stopAHAPPlayback()
#endif
        }
    }

    private func setupAnimation() {
        let vm = RiveViewModel(fileName: fileName, autoPlay: true)
        vm.fit = .layout
        vm.layoutScaleFactor = RiveViewModel.layoutScaleFactorAutomatic
        vm.riveModel?.enableAutoBind { instance in
            animationVMInstance = instance
            let connectedProperty = instance.booleanProperty(fromPath: "Connected")
            connectedProperty?.value = connected
        }
        animationVM = vm
    }

    private func animateProgress(to targetValue: Float) {
        progressAnimationTimer?.invalidate()

        let duration: TimeInterval = 3.0
        let frameRate: TimeInterval = 1.0 / 60.0
        let totalSteps = Int(duration / frameRate)
        let startValue = displayedProgress
        let delta = targetValue - startValue

        guard delta != 0, totalSteps > 0 else {
            displayedProgress = targetValue
            updateRiveProgress(targetValue)
            return
        }

        var currentStep = 0

        progressAnimationTimer = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true) { timer in
            currentStep += 1
            let progress = Float(currentStep) / Float(totalSteps)
            let easedProgress = 1 - pow(1 - progress, 3)
            let newValue = startValue + delta * easedProgress

            displayedProgress = newValue
            updateRiveProgress(newValue)

            if currentStep >= totalSteps {
                timer.invalidate()
                progressAnimationTimer = nil
                displayedProgress = targetValue
                updateRiveProgress(targetValue)
            }
        }
    }

    private func updateRiveProgress(_ value: Float) {
        let progressProperty = animationVMInstance?.numberProperty(fromPath: "progessPercentage")
        progressProperty?.value = value
    }
}
