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
    @State private var timer: Timer?
    
    @State private var workItem: DispatchWorkItem?

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
        
        
        workItem = DispatchWorkItem {
            isPressed = true
            HapticFeedbackManager.shared.startHapticFeedback(duration: longPressDuration, interval: 0.15)
            withAnimation(.easeIn(duration: longPressDuration)) {
                progress = 1.0
            }
            
            timer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { _ in
                onLongPressComplete()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem!)
    }
    
    func stopHold() {
        isPressed = false
        
        timer?.invalidate()
        timer = nil
        cancelWork()
        
        HapticFeedbackManager.shared.stopHapticFeedback()
        withAnimation(.easeOut(duration: 0.3)) {
            progress = 0.0
        }
    }
    
    func onLongPressComplete() {
        HapticFeedbackManager.shared.stopHapticFeedback()
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Delay for smoother transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            stopHold()
            longPressAction()
        }
    }
    
    func cancelWork() {
        workItem?.cancel()
        workItem = nil
    }
}
