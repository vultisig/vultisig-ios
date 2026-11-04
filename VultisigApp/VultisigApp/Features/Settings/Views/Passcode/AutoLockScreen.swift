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
                VStack(alignment: .leading, spacing: 8) {
                    Text("autoLockDescription".localized)
                        .settingsText(.footnote)
                        .foregroundStyle(Theme.colors.textSecondary)

                    ForEach(AutoLockInterval.selectableCases) { interval in
                        Button {
                            select(interval)
                        } label: {
                            row(for: interval)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .screenTitle("autoLockScreenTitle".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
    }

    private func row(for interval: AutoLockInterval) -> some View {
        HStack(spacing: 12) {
            Text(interval.titleKey.localized)
                .settingsText(.bodyS)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Icon(.selectionCheck, color: Theme.colors.textPrimary, size: 16)
                .background(Circle().fill(Theme.colors.primaryAccent3))
                .opacity(interval == selection ? 1 : 0)
                .accessibilityHidden(interval != selection)
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.lg.shape)
        .overlay(Theme.radius.lg.shape.strokeBorder(Theme.colors.borderExtraLight, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func select(_ interval: AutoLockInterval) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = interval
        }
        lockService.autoLockInterval = interval
    }
}
