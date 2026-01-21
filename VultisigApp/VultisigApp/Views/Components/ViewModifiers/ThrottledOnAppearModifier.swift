//
//  ThrottledOnAppearModifier.swift
//  VultisigApp
//
//  Created on 17/11/2025.
//

import SwiftUI

/// A view modifier that throttles `onAppear` actions to prevent excessive updates
/// when the view appears multiple times in quick succession.
struct ThrottledOnAppearModifier: ViewModifier {
    let interval: TimeInterval
    let action: () -> Void

    @State private var lastExecutionTime: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                let now = Date()

                // Check if enough time has passed since last execution
                if let lastTime = lastExecutionTime {
                    let timeSinceLastExecution = now.timeIntervalSince(lastTime)

                    if timeSinceLastExecution >= interval {
                        lastExecutionTime = now
                        action()
                    }
                } else {
                    // First time, always execute
                    lastExecutionTime = now
                    action()
                }
            }
    }
}

extension View {
    /// Executes an action when the view appears, throttled to a specified interval.
    ///
    /// This modifier prevents the action from executing more than once within the
    /// specified time interval, even if the view appears multiple times.
    ///
    /// - Parameters:
    ///   - interval: The minimum time interval (in seconds) between action executions
    ///   - action: The closure to execute when the view appears (respecting the throttle interval)
    ///
    /// - Returns: A view that executes the throttled action on appear
    ///
    /// Example:
    /// ```swift
    /// MyView()
    ///     .throttledOnAppear(interval: 5.0) {
    ///         // This will only execute once every 5 seconds, even if the view appears more frequently
    ///         refresh()
    ///     }
    /// ```
    func throttledOnAppear(interval: TimeInterval = 30, action: @escaping () -> Void) -> some View {
        modifier(ThrottledOnAppearModifier(interval: interval, action: action))
    }
}
