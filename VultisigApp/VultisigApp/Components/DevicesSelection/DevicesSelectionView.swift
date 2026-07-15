//
//  DevicesSelectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/07/2026.
//

import SwiftUI
import RiveRuntime

/// Shared "How many devices do you have?" selector used by both the
/// onboarding and reshare flows. Owns the Rive `devices_component`
/// lifecycle (fit `.layout`, `Index` number-property listener + iOS
/// haptic), the blue-glow background, and the tip-row + primary-button
/// chrome. Callers supply the selection binding, copy, button state, and
/// an optional overlay anchored to the bottom of the animation (used by
/// reshare for the threshold-not-met warning card).
struct DevicesSelectionView<Overlay: View>: View {
    @Binding private var selectedIndex: Int
    private let tipText: String
    private let buttonTitle: String
    private let isLoading: Bool
    private let isButtonDisabled: Bool
    private let onContinue: () -> Void
    private let overlay: () -> Overlay

    @State private var animationVM: RiveViewModel? = nil

    init(
        selectedIndex: Binding<Int>,
        tipText: String,
        buttonTitle: String,
        isLoading: Bool = false,
        isButtonDisabled: Bool = false,
        onContinue: @escaping () -> Void,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self._selectedIndex = selectedIndex
        self.tipText = tipText
        self.buttonTitle = buttonTitle
        self.isLoading = isLoading
        self.isButtonDisabled = isButtonDisabled
        self.onContinue = onContinue
        self.overlay = overlay
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                animationVM?.view()
                    .frame(maxWidth: 400)
                    .overlay(alignment: .bottom) {
                        overlay()
                    }
                Spacer()

                VStack(spacing: 16) {
                    tipView
                    PrimaryButton(
                        title: buttonTitle,
                        isLoading: isLoading,
                        action: onContinue
                    )
                    .disabled(isButtonDisabled)
                }
            }
            .padding(.top, 64)
        }
        .screenIgnoresTopEdge()
        .screenBackground(.clear)
        .background(DevicesSelectionBackground())
        .onLoad(perform: onLoad)
    }

    private var tipView: some View {
        HStack(spacing: 8) {
            Icon(named: "lightbulb", size: 12)
            Text(tipText)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
        }
    }

    private func onLoad() {
        animationVM = RiveViewModel(fileName: "devices_component")
        animationVM?.fit = .layout

        animationVM?.riveModel?.enableAutoBind { instance in
            instance.numberProperty(fromPath: "Index")?.addListener { value in
                selectedIndex = Int(value)
                #if os(iOS)
                HapticFeedbackManager.shared.startHapticFeedback(duration: 0.1)
                #endif
            }
        }
    }
}

extension DevicesSelectionView where Overlay == EmptyView {
    init(
        selectedIndex: Binding<Int>,
        tipText: String,
        buttonTitle: String,
        isLoading: Bool = false,
        isButtonDisabled: Bool = false,
        onContinue: @escaping () -> Void
    ) {
        self.init(
            selectedIndex: selectedIndex,
            tipText: tipText,
            buttonTitle: buttonTitle,
            isLoading: isLoading,
            isButtonDisabled: isButtonDisabled,
            onContinue: onContinue,
            overlay: { EmptyView() }
        )
    }
}
