//
//  HapticFeedbackManager.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI

#if os(iOS)
class HapticFeedbackManager {
    private var timer: Timer?
    private var stopWorkItem: DispatchWorkItem?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    static let shared = HapticFeedbackManager()
    
    private init() {}
    
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
