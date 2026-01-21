//
//  HapticFeedbackManager.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI
import CoreHaptics

#if os(iOS)
class HapticFeedbackManager {
    private var timer: Timer?
    private var stopWorkItem: DispatchWorkItem?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?

    static let shared = HapticFeedbackManager()

    private init() {
        setupHapticEngine()
    }

    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()

            // Handle engine reset
            hapticEngine?.resetHandler = { [weak self] in
                do {
                    try self?.hapticEngine?.start()
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }

            // Handle engine stopped
            hapticEngine?.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason)")
            }
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }

    func playAHAPFile(named fileName: String, looping: Bool = false) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "ahap") else {
            print("AHAP file '\(fileName).ahap' not found")
            return
        }

        do {
            // Ensure engine is running (calling start on an already running engine is safe)
            try hapticEngine?.start()

            // Load the AHAP pattern from file
            let pattern = try CHHapticPattern(contentsOf: url)

            // Create advanced player with the pattern to support looping
            hapticPlayer = try hapticEngine?.makeAdvancedPlayer(with: pattern)

            // Enable looping if requested
            hapticPlayer?.loopEnabled = looping

            // Play the pattern
            try hapticPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play AHAP file: \(error)")
        }
    }

    func stopAHAPPlayback() {
        do {
            try hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
            hapticPlayer = nil
        } catch {
            print("Failed to stop AHAP playback: \(error)")
        }
    }

    func startHapticFeedback(duration: TimeInterval, interval: TimeInterval = 0.1) {
        // Stop any existing feedback first
        stopHapticFeedback()

        // Prepare the generator for better performance
        impactGenerator.prepare()

        // Start immediately
        impactGenerator.impactOccurred()

        // Continue with timer
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.impactGenerator.impactOccurred()
        }

        // Stop after duration
        stopWorkItem = DispatchWorkItem {
            self.stopHapticFeedback()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: stopWorkItem!)
    }

    func stopHapticFeedback() {
        timer?.invalidate()
        timer = nil
        stopWorkItem?.cancel()
        stopWorkItem = nil
    }
}
#endif
