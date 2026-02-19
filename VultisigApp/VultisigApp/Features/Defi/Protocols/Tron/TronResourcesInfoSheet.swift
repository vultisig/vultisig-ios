//
//  TronResourcesInfoSheet.swift
//  VultisigApp
//
//  Bandwidth & Energy help modal with accordion sections.
//

import SwiftUI

struct TronResourcesInfoSheet: View {
    var onClose: () -> Void

    @State private var bandwidthExpanded = true
    @State private var energyExpanded = false

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    bandwidthSection
                    energySection
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }

            learnMoreButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.colors.bgSurface1)
        .background(Theme.colors.bgSurface1)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("tron")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            Text("TRON")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)

            Text(NSLocalizedString("tronResourcesInfoTitle", comment: "Bandwidth & Energy"))
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    // MARK: - Accordion Sections

    private var bandwidthSection: some View {
        accordionSection(
            icon: "gauge.with.needle",
            title: NSLocalizedString("tronBandwidth", comment: "Bandwidth"),
            accentColor: Theme.colors.alertSuccess,
            description: NSLocalizedString("tronBandwidthDescription", comment: "Bandwidth description"),
            isExpanded: $bandwidthExpanded
        )
    }

    private var energySection: some View {
        accordionSection(
            icon: "bolt.fill",
            title: NSLocalizedString("tronEnergy", comment: "Energy"),
            accentColor: Theme.colors.alertWarning,
            description: NSLocalizedString("tronEnergyDescription", comment: "Energy description"),
            isExpanded: $energyExpanded
        )
    }

    private func accordionSection(
        icon: String,
        title: String,
        accentColor: Color,
        description: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: icon)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(accentColor)
                    }

                    Text(title)
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(accentColor)

                    Spacer()

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded.wrappedValue {
                Divider()
                    .overlay(Theme.colors.textSecondary.opacity(0.2))

                Text(description)
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TronConstants.Design.cornerRadius)
                .stroke(Theme.colors.textSecondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Learn More Button

    private var learnMoreButton: some View {
        PrimaryButton(
            title: NSLocalizedString("learnMore", comment: "Learn more"),
            type: .secondary
        ) {
            if let url = URL(string: "https://developers.tron.network/docs/resource-model") {
                openURL(url)
            }
        }
    }
}
