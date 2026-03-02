//
//  ForegroundNotificationBannerView.swift
//  VultisigApp
//

import SwiftUI

struct ForegroundNotificationBannerView: View {
    let data: ForegroundNotificationData
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            bannerBackground
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 40,
                        bottomTrailingRadius: 40
                    )
                )
            VStack(spacing: 11) {
                iconCircle
                titleLabel
                vaultPill
                descriptionLabel
            }
            .padding(.bottom, 24)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .offset(y: 32)
        }
        .offset(y: dragOffset)
        .gesture(swipeUpGesture)
        .onTapGesture { onTap() }
        .ignoresSafeArea(.all)
        .frame(height: 200)
    }

    // MARK: - Subviews

    private var iconCircle: some View {
        VaultSetupStepIcon(state: .active, icon: data.iconName, isSmall: true)
    }

    private var titleLabel: some View {
        Text("joinKeysign".localized)
            .font(Theme.fonts.title3)
            .foregroundStyle(Theme.colors.textPrimary)
    }

    private var vaultPill: some View {
        HStack(spacing: 6) {
            VaultIconTypeView(isFastVault: data.isFastVault)
            Text(data.vaultName)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.colors.bgSurface2)
        .clipShape(Capsule())
    }

    private var descriptionLabel: some View {
        Text(data.description)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Background

    private var bannerBackground: some View {
        ZStack {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color(hex: "4879FD"), location: 0.00),
                    Gradient.Stop(color: Color(hex: "0439C7"), location: 1.00)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )

            Image("magic-pattern")
                .resizable()
                .scaledToFill()
                .frame(maxHeight: 200)
                .showIf(!isMacOS)
        }
    }

    // MARK: - Gesture

    private var swipeUpGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height < 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height < -50 {
                    onDismiss()
                } else {
                    withAnimation(.spring()) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Platform

    private var topPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 20
        #endif
    }
}
