import ActivityKit
import SwiftUI
import VultisigUIResources
import WidgetKit

struct TransactionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransactionActivityAttributes.self) { context in
            TransactionActivityCard(state: context.state)
                .padding(16)
                .activityBackgroundTint(WidgetTheme.background)
                .activitySystemActionForegroundColor(WidgetTheme.primaryText)
                .widgetURL(TransactionActivityLink.url(recordID: context.attributes.recordID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TransactionActivityBrand()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TransactionActivityStatus(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TransactionActivityCard(state: context.state, showsHeader: false)
                }
            } compactLeading: {
                HStack(spacing: 0) { WidgetBrandMark(size: 18) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(String(localized: "widget.brand")))
            } compactTrailing: {
                TransactionActivityStatus(state: context.state, showsText: false)
            } minimal: {
                TransactionActivityStatus(state: context.state, showsText: false)
            }
            .widgetURL(TransactionActivityLink.url(recordID: context.attributes.recordID))
        }
    }
}

private struct TransactionActivityBrand: View {
    var body: some View {
        HStack(spacing: 6) {
            WidgetBrandMark(size: 20)
            Text(String(localized: "widget.brand"))
                .font(WidgetTheme.labelFont(size: 13))
                .foregroundStyle(WidgetTheme.primaryText)
        }
        .fixedSize()
    }
}

private struct TransactionActivityStatus: View {
    let state: TransactionActivityState
    var showsText = true
    var fontSize: CGFloat = 11

    private var status: TransactionActivityState.DisplayStatus { state.phase.displayStatus }
    private var symbolName: String {
        switch status {
        case .inProgress: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }
    private var color: Color {
        switch status {
        case .inProgress: WidgetTheme.activityAccent
        case .success: WidgetTheme.positive
        case .failed: WidgetTheme.negative
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            if showsText { Text(LocalizedStringKey(status.localizationKey)) }
        }
        .font(WidgetTheme.labelFont(size: fontSize))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(status.localizationKey)))
    }
}

struct TransactionActivityCard: View {
    let state: TransactionActivityState
    var showsHeader = true

    var body: some View {
        ViewThatFits(in: .vertical) {
            card(showsDetails: true)
            card(showsDetails: false)
        }
        // The system truncates Lock Screen cards above 160 points, including padding.
        .frame(maxHeight: 128)
        .foregroundStyle(WidgetTheme.primaryText)
        .accessibilityElement(children: .combine)
    }

    private func card(showsDetails: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack(spacing: 8) {
                    TransactionActivityBrand()
                    Spacer(minLength: 4)
                    if let operation = state.operation {
                        Text(LocalizedStringKey(operation.localizationKey))
                            .font(WidgetTheme.labelFont(size: 12))
                            .foregroundStyle(WidgetTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            route(showsDetails: showsDetails)
            if showsHeader || (showsDetails && (state.fee != nil || state.elapsedTimeAnchor != nil)) {
                Rectangle().fill(WidgetTheme.separator).frame(height: 0.5)
                footer(showsDetails: showsDetails)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hasDestination: Bool {
        (state.operation == .swap || state.operation == .limit)
            && state.sourceSummary != nil && state.destinationTicker?.isEmpty == false
    }

    private var hasRecipient: Bool { state.operation == .send && state.recipient != nil }

    private func route(showsDetails: Bool) -> some View {
        HStack(spacing: 8) {
            if let summary = state.summary {
                assetColumn(title: state.sourceSummary ?? summary,
                            subtitle: showsDetails ? state.network : nil,
                            assetID: state.sourceAssetID, imageKey: state.sourceImageKey)
                    .layoutPriority(1)
                if hasDestination || hasRecipient {
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(WidgetTheme.iconFont(size: 16))
                        .foregroundStyle(WidgetTheme.secondaryText)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    if hasDestination, let ticker = state.destinationTicker {
                        // History does not store the destination network. Do not infer it from a ticker or logo.
                        assetColumn(title: ticker, subtitle: showsDetails && state.provider != state.network ? state.provider : nil,
                                    assetID: state.destinationAssetID, imageKey: state.destinationImageKey)
                            .frame(maxWidth: 125)
                            .layoutPriority(1)
                    } else if let recipient = state.recipient {
                        recipientColumn(recipient, showsDetails: showsDetails)
                            .frame(maxWidth: 125)
                            .layoutPriority(1)
                    }
                }
            } else {
                Image(systemName: "lock.shield")
                    .font(WidgetTheme.iconFont(size: 24))
                    .foregroundStyle(WidgetTheme.activityAccent)
                    .accessibilityHidden(true)
                Text("transactionActivityTitle")
                    .font(WidgetTheme.labelFont(size: 19))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private func assetColumn(title: String, subtitle: String?, assetID: String?, imageKey: String?) -> some View {
        HStack(spacing: 7) {
            tokenAvatar(assetID, imageKey: imageKey, size: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(WidgetTheme.priceFont(size: 20))
                    .minimumScaleFactor(0.65)
                    .truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WidgetTheme.labelFont(size: 11))
                        .foregroundStyle(WidgetTheme.secondaryText)
                        .minimumScaleFactor(0.8)
                }
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func recipientColumn(_ recipient: String, showsDetails: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "person")
                .font(WidgetTheme.iconFont(size: 20))
                .foregroundStyle(WidgetTheme.secondaryText)
                .frame(width: 32, height: 32)
                .background(WidgetTheme.activitySurface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipient).font(WidgetTheme.priceFont(size: 17))
                if showsDetails {
                    Text("recipient")
                        .font(WidgetTheme.labelFont(size: 11))
                        .foregroundStyle(WidgetTheme.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private func footer(showsDetails: Bool) -> some View {
        HStack(spacing: 8) {
            if showsHeader {
                TransactionActivityStatus(state: state, fontSize: 12)
                    .layoutPriority(1)
            }
            if showsDetails, let anchor = state.elapsedTimeAnchor {
                Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
                    .font(WidgetTheme.labelFont(size: 11))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if showsDetails, let fee = state.fee {
                HStack(spacing: 4) {
                    Text("transactionActivityFee")
                    Text(fee)
                }
                .font(WidgetTheme.labelFont(size: 11))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }

    private func tokenAvatar(_ assetID: String?, imageKey: String?, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(WidgetTheme.activitySurface)
            if let safeID = TransactionActivityState.bundledAssetID(for: assetID),
               let image = VultisigResources.image(named: safeID) {
                image.resizable().scaledToFit()
            } else if let key = TransactionActivityState.validatedImageKey(imageKey),
                      let data = SharedImageLoading.cache.data(forKey: key),
                      let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                // A neutral asset glyph avoids assigning a known logo by ticker alone.
                Image(systemName: "circle.hexagongrid.fill")
                    .font(WidgetTheme.iconFont(size: size * 0.48))
                    .foregroundStyle(WidgetTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsHeader { Circle().stroke(WidgetTheme.background, lineWidth: 2) }
        }
    }
}

#if DEBUG
private enum TransactionActivityPreview {
    static func state(swap: Bool = false, privateMode: Bool = false, delayed: Bool = false,
                      phase: TransactionActivityState.Phase = .pending) -> TransactionActivityState {
        TransactionActivityState(
            phase: phase, observedAt: Date().addingTimeInterval(delayed ? -120 : 0), revision: 1, updateDelayed: delayed,
            summary: swap ? "125.123456 USDC → ETH" : "125.123456 USDC", network: "Base", showDetails: !privateMode,
            operation: swap ? .swap : .send, recipient: swap ? nil : "0x1234567890123456789012345678901234567890",
            fee: "0.000004 ETH", provider: swap ? "SwapKit" : nil, submittedAt: Date().addingTimeInterval(-35),
            sourceAssetID: "usdc", destinationAssetID: swap ? "eth" : nil,
            sourceSummary: "125.123456 USDC", destinationTicker: swap ? "ETH" : nil
        )
    }
}

#Preview("Transfer", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
    TransactionLiveActivityWidget()
} contentStates: {
    TransactionActivityPreview.state()
}

#Preview("Swap", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
    TransactionLiveActivityWidget()
} contentStates: {
    TransactionActivityPreview.state(swap: true, phase: .sourceConfirmed)
}

#Preview("Private", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
    TransactionLiveActivityWidget()
} contentStates: {
    TransactionActivityPreview.state(privateMode: true)
}

#Preview("Stale in progress", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
    TransactionLiveActivityWidget()
} contentStates: {
    TransactionActivityPreview.state(delayed: true)
}

#Preview("Failure", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
    TransactionLiveActivityWidget()
} contentStates: {
    TransactionActivityPreview.state(phase: .failed)
}
#endif
