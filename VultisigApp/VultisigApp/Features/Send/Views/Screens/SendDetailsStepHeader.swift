//
//  SendDetailsStepHeader.swift
//  VultisigApp
//

import SwiftUI

/// The Send step icons and, under them, the title of the step on screen.
struct SendDetailsStepHeader: View {
    let viewModel: SendDetailsViewModel
    /// The title follows the displayed step, so it crossfades inside the pane swap.
    let displayedTab: SendDetailsFocusedTab?
    let horizontalInset: CGFloat

    private static let stepIndicatorTopPadding: CGFloat = 8
    private static let stepTitleTopPadding: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, Self.stepIndicatorTopPadding)

            stepTitle
                .padding(.top, Self.stepTitleTopPadding)
                .padding(.horizontal, horizontalInset)
        }
    }

    private var stepIndicator: some View {
        let steps = SendDetailsFocusedTab.allCases
        return StepIndicatorView(
            icons: steps.map(\.icon),
            labels: steps.map(\.label),
            animatesStateChanges: true,
            iconSize: .compact,
            state: { viewModel.stepState(for: steps[$0]) },
            canSelect: { viewModel.canNavigate(to: steps[$0]) },
            onSelect: { viewModel.onSelect(tab: steps[$0]) }
        )
    }

    @ViewBuilder
    private var stepTitle: some View {
        if let tab = displayedTab {
            Text(tab.title)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
        }
    }
}

private extension SendDetailsFocusedTab {
    var icon: ImageResource {
        switch self {
        case .asset: .coins
        case .address: .pinFilled
        case .amount: .calculator
        }
    }

    var label: String {
        switch self {
        case .asset: "asset".localized
        case .address: "address".localized
        case .amount: "amount".localized
        }
    }

    var title: String {
        switch self {
        case .asset: "chooseAnAsset".localized
        case .address: "enterTheAddress".localized
        case .amount: "enterTheAmount".localized
        }
    }
}
