//
//  DebounceHelper.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-18.
//

import SwiftUI

class DebounceHelper {
    static let shared = DebounceHelper()
    private var workItem: DispatchWorkItem?

    func debounce(delay: TimeInterval = 0.5, action: @escaping () -> Void) {
        workItem?.cancel()
        let task = DispatchWorkItem { action() }
        workItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
}
