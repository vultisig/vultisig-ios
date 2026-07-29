//
//  AutoLockScreen.swift
//  VultisigApp
//

import SwiftUI

/// How long the app may sit in the background before it locks again.
struct AutoLockScreen: View {

    @State private var selection: AutoLockInterval
    private let lockService: AppLockService

    init(lockService: AppLockService = .shared) {
        self.lockService = lockService
        _selection = State(initialValue: lockService.autoLockInterval)
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                SettingsSectionContainerView {
                    VStack(spacing: .zero) {
                        ForEach(AutoLockInterval.allCases) { interval in
                            Button {
                                select(interval)
                            } label: {
                                SettingSelectionCell(
                                    title: interval.titleKey.localized,
                                    isSelected: interval == selection,
                                    showSeparator: interval != AutoLockInterval.allCases.last
                                )
                            }
                        }
                    }
                }
            }
        }
        .screenTitle("passcodeAutoLockTitle".localized)
        .screenBackground(.gradient)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
    }

    private func select(_ interval: AutoLockInterval) {
        selection = interval
        lockService.autoLockInterval = interval
    }
}
