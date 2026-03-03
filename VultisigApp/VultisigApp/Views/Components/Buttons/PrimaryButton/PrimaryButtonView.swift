//
//  PrimaryButtonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryButtonView<LeadingView: View, TrailingView: View>: View {
    let title: String
    let leadingView: LeadingView
    let trailingView: TrailingView
    let isLoading: Bool
    let paddingLeading: CGFloat
    let reserveTrailingIconSpace: Bool

    init(
        title: String,
        @ViewBuilder leadingView: () -> LeadingView,
        @ViewBuilder trailingView: () -> TrailingView,
        isLoading: Bool = false,
        paddingLeading: CGFloat = 0,
        reserveTrailingIconSpace: Bool = false
    ) {
        self.title = title
        self.leadingView = leadingView()
        self.trailingView = trailingView()
        self.isLoading = isLoading
        self.paddingLeading = paddingLeading
        self.reserveTrailingIconSpace = reserveTrailingIconSpace
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            leadingView
            Text(NSLocalizedString(title, comment: "Button Text"))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, paddingLeading)
            trailingView
            if reserveTrailingIconSpace, TrailingView.self == EmptyView.self {
                Icon(named: "check", color: .clear, size: 15)
            }
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - No icons

extension PrimaryButtonView where LeadingView == EmptyView, TrailingView == EmptyView {
    init(
        title: String,
        isLoading: Bool = false,
        paddingLeading: CGFloat = 0,
        reserveTrailingIconSpace: Bool = false
    ) {
        self.init(
            title: title,
            leadingView: { EmptyView() },
            trailingView: { EmptyView() },
            isLoading: isLoading,
            paddingLeading: paddingLeading,
            reserveTrailingIconSpace: reserveTrailingIconSpace
        )
    }
}

// MARK: - Leading icon string

extension PrimaryButtonView where LeadingView == Icon, TrailingView == EmptyView {
    init(
        title: String,
        leadingIcon: String,
        isLoading: Bool = false,
        paddingLeading: CGFloat = 0,
        reserveTrailingIconSpace: Bool = false
    ) {
        self.init(
            title: title,
            leadingView: { Icon(named: leadingIcon, color: Theme.colors.textPrimary, size: 15) },
            trailingView: { EmptyView() },
            isLoading: isLoading,
            paddingLeading: paddingLeading,
            reserveTrailingIconSpace: reserveTrailingIconSpace
        )
    }
}

// MARK: - Trailing icon string

extension PrimaryButtonView where LeadingView == EmptyView, TrailingView == Icon {
    init(
        title: String,
        trailingIcon: String,
        isLoading: Bool = false,
        paddingLeading: CGFloat = 0,
        reserveTrailingIconSpace: Bool = false
    ) {
        self.init(
            title: title,
            leadingView: { EmptyView() },
            trailingView: { Icon(named: trailingIcon, color: Theme.colors.textPrimary, size: 15) },
            isLoading: isLoading,
            paddingLeading: paddingLeading,
            reserveTrailingIconSpace: reserveTrailingIconSpace
        )
    }
}

#Preview {
    PrimaryButtonView(title: "Next")
}
