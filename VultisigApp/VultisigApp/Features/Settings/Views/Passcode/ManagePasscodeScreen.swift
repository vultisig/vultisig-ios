//
//  ManagePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Settings entry point for the passcode: turn it on, change it, turn it off,
/// and reach the auto-lock interval once it is on.
struct ManagePasscodeScreen: View {

    @Environment(\.router) var router
    @State private var isSet: Bool = false
    @State private var showDisable = false

    private let service: PasscodeService
    private let lockService: AppLockService

    init(service: PasscodeService = .shared, lockService: AppLockService = .shared) {
        self.service = service
        self.lockService = lockService
    }

    /// The rows on offer, which depend on whether a passcode exists. Kept as an
    /// array rather than branching in the view body so each row can tell the
    /// shared list container where it sits, which is what rounds the end rows
    /// and draws the separators between them.
    private var rows: [Row] {
        isSet ? [.change, .autoLock, .disable] : [.set]
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: .zero) {
                        ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                            Button {
                                handle(row)
                            } label: {
                                SettingsCommonOptionView(
                                    icon: .lockPassword,
                                    title: row.title,
                                    type: .normal
                                )
                            }
                            .commonListItemContainer(index: index, itemsCount: rows.count)
                        }
                    }
                    .commonListContainer()

                    explanation
                }
            }
        }
        .screenTitle("passcodeManageTitle".localized)
        .screenBackground(.gradient)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        .crossPlatformSheet(isPresented: $showDisable) {
            DisablePasscodeScreen()
        }
        // `.onAppear` as well as `.task`: returning from the pushed set/change
        // screens does not re-run `.task`, and a stale `isSet` would keep
        // offering "Set passcode" after one had just been set.
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        .onChange(of: showDisable) { _, isShowing in
            guard !isShowing else { return }
            Task { await refresh() }
        }
    }

    /// States plainly what the passcode does and does not do. Encryption is what
    /// the passcode buys — with none set the key shares sit in the clear, and
    /// removing it puts them back — and it is still not a backup, which a user
    /// who believes otherwise may relax their habits over.
    private var explanation: some View {
        Text("passcodeManageExplanation".localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Row: Hashable {
        case set
        case change
        case autoLock
        case disable

        var title: String {
            switch self {
            case .set: "passcodeSetTitle".localized
            case .change: "passcodeChangeTitle".localized
            case .autoLock: "passcodeAutoLockTitle".localized
            case .disable: "passcodeDisableNavTitle".localized
            }
        }
    }

    private func handle(_ row: Row) {
        switch row {
        case .set:
            router.navigate(to: SettingsRoute.setPasscode)
        case .change:
            router.navigate(to: SettingsRoute.changePasscode)
        case .autoLock:
            router.navigate(to: SettingsRoute.autoLock)
        case .disable:
            showDisable = true
        }
    }

    private func refresh() async {
        isSet = await service.isSet
    }
}
