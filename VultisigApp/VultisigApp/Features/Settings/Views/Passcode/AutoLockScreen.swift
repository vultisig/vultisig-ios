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

    private var intervals: [AutoLockInterval] { AutoLockInterval.allCases }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: .zero) {
                    ForEach(Array(intervals.enumerated()), id: \.element) { index, interval in
                        Button {
                            select(interval)
                        } label: {
                            SettingSelectionCell(
                                title: interval.titleKey.localized,
                                isSelected: interval == selection
                            )
                        }
                        .commonListItemContainer(index: index, itemsCount: intervals.count)
                    }
                }
                .commonListContainer()
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
