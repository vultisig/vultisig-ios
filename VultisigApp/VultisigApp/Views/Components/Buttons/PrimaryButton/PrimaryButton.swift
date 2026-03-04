//
//  PrimaryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/07/2025.
//

import SwiftUI

struct PrimaryButton<LeadingView: View, TrailingView: View>: View {
    let title: String
    let leadingView: LeadingView
    let trailingView: TrailingView
    let isLoading: Bool
    let type: ButtonType
    let size: ButtonSize
    let action: () -> Void
    let reserveTrailingIconSpace: Bool

    let supportsLongPress: Bool
    @Binding var longPressProgress: CGFloat

    init(
        title: String,
        @ViewBuilder leadingView: () -> LeadingView,
        @ViewBuilder trailingView: () -> TrailingView,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.leadingView = leadingView()
        self.trailingView = trailingView()
        self.isLoading = isLoading
        self.type = type
        self.size = size
        self.reserveTrailingIconSpace = reserveTrailingIconSpace
        self.supportsLongPress = supportsLongPress
        self._longPressProgress = longPressProgress
        self.action = action
    }

    var body: some View {
        Button {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            PrimaryButtonView(
                title: title,
                leadingView: { leadingView },
                trailingView: { trailingView },
                isLoading: isLoading,
                reserveTrailingIconSpace: reserveTrailingIconSpace
            )
        }
        .buttonStyle(
            PrimaryButtonStyle(
                type: type,
                size: size,
                supportsLongPress: supportsLongPress,
                progress: $longPressProgress
            )
        )
    }
}

// MARK: - No icons

extension PrimaryButton where LeadingView == EmptyView, TrailingView == EmptyView {
    init(
        title: String,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: { EmptyView() },
            trailingView: { EmptyView() },
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

// MARK: - Leading icon string

extension PrimaryButton where LeadingView == Icon, TrailingView == EmptyView {
    init(
        title: String,
        leadingIcon: String,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: { Icon(named: leadingIcon, color: Theme.colors.textPrimary, size: 15) },
            trailingView: { EmptyView() },
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

// MARK: - Trailing icon string

extension PrimaryButton where LeadingView == EmptyView, TrailingView == Icon {
    init(
        title: String,
        trailingIcon: String,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: { EmptyView() },
            trailingView: { Icon(named: trailingIcon, color: Theme.colors.textPrimary, size: 15) },
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

// MARK: - Both icon strings

extension PrimaryButton where LeadingView == Icon, TrailingView == Icon {
    init(
        title: String,
        leadingIcon: String,
        trailingIcon: String,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: { Icon(named: leadingIcon, color: Theme.colors.textPrimary, size: 15) },
            trailingView: { Icon(named: trailingIcon, color: Theme.colors.textPrimary, size: 15) },
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

// MARK: - Leading view only

extension PrimaryButton where TrailingView == EmptyView {
    init(
        title: String,
        @ViewBuilder leadingView: () -> LeadingView,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: leadingView,
            trailingView: { EmptyView() },
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

// MARK: - Leading icon string + trailing view

extension PrimaryButton where LeadingView == Icon {
    init(
        title: String,
        leadingIcon: String,
        @ViewBuilder trailingView: () -> TrailingView,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: { Icon(named: leadingIcon, color: Theme.colors.textPrimary, size: 15) },
            trailingView: trailingView,
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

// MARK: - Trailing view only

extension PrimaryButton where LeadingView == EmptyView {
    init(
        title: String,
        @ViewBuilder trailingView: () -> TrailingView,
        isLoading: Bool = false,
        type: ButtonType = .primary,
        size: ButtonSize = .medium,
        reserveTrailingIconSpace: Bool = false,
        supportsLongPress: Bool = false,
        longPressProgress: Binding<CGFloat> = .constant(0),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            leadingView: { EmptyView() },
            trailingView: trailingView,
            isLoading: isLoading,
            type: type,
            size: size,
            reserveTrailingIconSpace: reserveTrailingIconSpace,
            supportsLongPress: supportsLongPress,
            longPressProgress: longPressProgress,
            action: action
        )
    }
}

#Preview {
    VStack {
        PrimaryButton(title: "Continue", type: .primary, size: .medium) {}
        PrimaryButton(title: "Continue", type: .primary, size: .small) {}
        PrimaryButton(title: "Continue", type: .primary, size: .mini) {}

        PrimaryButton(title: "Continue", type: .secondary, size: .medium) {}
        PrimaryButton(title: "Continue", type: .secondary, size: .small) {}
        PrimaryButton(title: "Continue", type: .secondary, size: .mini) {}
    }
}
