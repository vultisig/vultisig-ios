//
//  HapticFeedbackManager.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/07/2025.
//

import SwiftUI

class HapticFeedbackManager {
    private var timer: Timer?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    static let shared = HapticFeedbackManager()
    
    private init() {}
    
    func startHapticFeedback(duration: TimeInterval, interval: TimeInterval = 0.1) {
        // Prepare the generator for better performance
        impactGenerator.prepare()
        
        // Start immediately
        impactGenerator.impactOccurred()
        
        // Continue with timer
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.impactGenerator.impactOccurred()
        }
        
        // Stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.stopHapticFeedback()
        }
    }
    
    func stopHapticFeedback() {
        timer?.invalidate()
        timer = nil
    }
}
