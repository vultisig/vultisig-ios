//
//  SendDetailsScreen+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

#if os(iOS)
import SwiftUI

extension SendDetailsScreen {
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    var container: some View {
        Screen(title: "send".localized) {
            content
        }
    }

    var view: some View {
        ZStack(alignment: .bottom) {
            tabs
            buttonContainer
        }
    }

    var buttonContainer: some View {
        button
            .padding(.vertical, 8)
            .background(keyboardObserver.keyboardHeight == 0 ? .clear : Theme.colors.bgPrimary)
            .shadow(color: Theme.colors.bgPrimary, radius: keyboardObserver.keyboardHeight == 0 ? 0 : 15)
    }

    func setData() {
        keyboardObserver.keyboardHeight = 0
        Task {
            await getBalance()
        }
    }

    private func getButtonBackground() -> Color {
        if keyboardObserver.keyboardHeight == 0 {
            return Color.clear
        } else {
            return Theme.colors.bgPrimary
        }
    }
}
#endif
