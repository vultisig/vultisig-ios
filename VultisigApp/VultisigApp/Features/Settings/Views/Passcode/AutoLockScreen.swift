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

    /// Keep a migrated legacy choice visible until the user replaces it, so the
    /// selected policy is never hidden or silently rewritten by the redesign.
    private var intervals: [AutoLockInterval] {
        AutoLockInterval.pickerCases(current: selection)
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("autoLockDescription".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)

                    ForEach(intervals) { interval in
                        Button {
                            select(interval)
                        } label: {
                            SettingSelectionCell(
                                title: interval.titleKey.localized,
                                isSelected: interval == selection
                            )
                        }
                        .background(Theme.colors.bgSurface1)
                        .clipShape(Theme.radius.md.shape)
                    }
                }
            }
        }
        .screenTitle("autoLockScreenTitle".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
    }

    private func select(_ interval: AutoLockInterval) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = interval
        }
        lockService.autoLockInterval = interval
    }
}
