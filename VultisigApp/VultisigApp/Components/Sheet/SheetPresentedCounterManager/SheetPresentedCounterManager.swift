//
//  SheetPresentedCounterManager.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/10/2025.
//

import Foundation

// Observable object to manage sheet counter state
class SheetPresentedCounterManager: ObservableObject {
    @Published var counter: Int = 0
    /// Sheets presented with `SheetBackdrop.dimOnly`. Counted apart from
    /// `counter` so a blurring sheet stacked on one still blurs, and so
    /// resetting one count never clears the other.
    @Published var dimOnlyCounter: Int = 0

    func increment() {
        self.counter += 1
    }

    func decrement() {
        guard counter > 0 else { return }
        self.counter -= 1
    }

    func resetCounter() {
        guard self.counter != 0 else { return }
        self.counter = 0
    }

    func count(for backdrop: SheetBackdrop) -> Int {
        switch backdrop {
        case .blurred:
            return counter
        case .dimOnly:
            return dimOnlyCounter
        }
    }

    func increment(for backdrop: SheetBackdrop) {
        switch backdrop {
        case .blurred:
            increment()
        case .dimOnly:
            dimOnlyCounter += 1
        }
    }

    func decrement(for backdrop: SheetBackdrop) {
        switch backdrop {
        case .blurred:
            decrement()
        case .dimOnly:
            guard dimOnlyCounter > 0 else { return }
            dimOnlyCounter -= 1
        }
    }

    func resetCounter(for backdrop: SheetBackdrop) {
        switch backdrop {
        case .blurred:
            resetCounter()
        case .dimOnly:
            guard dimOnlyCounter != 0 else { return }
            dimOnlyCounter = 0
        }
    }

    /// Clears both counts, for the moments no sheet can be up.
    func resetAllCounters() {
        resetCounter(for: .blurred)
        resetCounter(for: .dimOnly)
    }
}
