//
//  TronResourcesInfoSheet.swift
//  VultisigApp
//
//  Bandwidth & Energy help modal with accordion sections.
//

import SwiftUI

struct TronResourcesInfoSheet: View {

    let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    @State private var expandedSection: TronResourceType? = .bandwidth

    @Environment(\.openURL) var openURL

    private let learnMoreURL = URL(string: "https://developers.tron.network/docs/resource-model")

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    accordion
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            learnMoreButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.colors.bgSurface1)
        .background(Theme.colors.bgSurface1)
        .presentationDragIndicator(.visible)
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    onDismiss?()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                Image("tron")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("TRON")
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            Text("tronResourcesInfoTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Accordion

    private var accordion: some View {
        VStack(spacing: 12) {
            accordionSection(
                resource: .bandwidth,
                icon: "gauge-2",
                title: "tronBandwidth".localized,
                accentColor: Theme.colors.alertSuccess,
                description: "tronBandwidthDescription".localized
            )

            accordionSection(
                resource: .energy,
                icon: "bolt",
                title: "tronEnergy".localized,
                accentColor: Theme.colors.alertWarning,
                description: "tronEnergyDescription".localized
            )
        }
    }

    private func accordionSection(
        resource: TronResourceType,
        icon: String,
        title: String,
        accentColor: Color,
        description: String
    ) -> some View {
        let isExpanded = expandedSection == resource

        return VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    // Opening one section collapses the other.
                    expandedSection = isExpanded ? nil : resource
                }
            } label: {
                HStack(spacing: 8) {
                    iconChip(icon: icon, accentColor: accentColor)

                    Text(title)
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(accentColor)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .overlay(Theme.colors.bgSurface2)

                    Text(description)
                        .font(Theme.fonts.bodySRegular)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.verticalGrow)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, isExpanded ? 24 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.bgSurface2, lineWidth: 1)
        )
    }

    private func iconChip(icon: String, accentColor: Color) -> some View {
        Image(icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(accentColor)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.1))
            )
    }

    // MARK: - Learn More Button

    private var learnMoreButton: some View {
        PrimaryButton(
            title: "learnMore".localized,
            type: .secondary
        ) {
            if let learnMoreURL {
                openURL(learnMoreURL)
            }
        }
    }
}

private extension AnyTransition {
    /// Vertical grow + fade used by the resource accordion: the content
    /// scales open from the top edge while fading in, instead of merely
    /// sliding or fading.
    static var verticalGrow: AnyTransition {
        .modifier(
            active: VerticalGrowModifier(progress: 0),
            identity: VerticalGrowModifier(progress: 1)
        )
    }
}

private struct VerticalGrowModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: progress, anchor: .top)
            .opacity(Double(progress))
    }
}
