//
//  KeyboardObserver.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

import SwiftUI
import Combine

final class KeyboardObserver: ObservableObject {

    @MainActor @Published var keyboardHeight: CGFloat = 0

    private var cancellables: Set<AnyCancellable> = []

    init() {
#if os(iOS)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
            .map { $0.height }
            .sink { [weak self] in self?.setKeyboardHeight($0) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
            .sink { [weak self] in self?.setKeyboardHeight($0) }
            .store(in: &cancellables)
#endif
    }

#if os(iOS)
    /// UIKit posts keyboard notifications on the main thread, so the height is
    /// set synchronously there rather than a run-loop turn later.
    private func setKeyboardHeight(_ height: CGFloat) {
        MainActor.assumeIsolated { keyboardHeight = height }
    }
#endif
}
