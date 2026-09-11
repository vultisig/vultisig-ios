import ActivityKit
import SwiftUI
import VultisigUIResources
import WidgetKit

struct TransactionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransactionActivityAttributes.self) { context in
            TransactionActivityCard(state: context.state, isStale: context.isStale)
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
                    TransactionActivityStatus(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TransactionActivityCard(state: context.state, isStale: context.isStale, showsHeader: false)
                }
            } compactLeading: {
                HStack(spacing: 0) { WidgetBrandMark(size: 18) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(String(localized: "widget.brand")))
            } compactTrailing: {
                TransactionActivityStatus(state: context.state, isStale: context.isStale, showsText: false)
            } minimal: {
                TransactionActivityStatus(state: context.state, isStale: context.isStale, showsText: false)
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
    let isStale: Bool
    var showsText = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var delayed: Bool { !state.phase.isTerminal && (isStale || state.updateDelayed) }
    private var statusLabel: Text {
        let phase = Text(LocalizedStringKey(state.phase.localizationKey))
        return delayed ? phase + Text(" · ") + Text("transactionActivityDelayed") : phase
    }
    private var symbolName: String { delayed ? "clock" : state.phase.symbol }
    private var animates: Bool { !reduceMotion && !isLuminanceReduced && !delayed && !state.phase.isTerminal }
    private var color: Color {
        if delayed { return WidgetTheme.warning }
        switch state.phase {
        case .confirmed, .completed: return WidgetTheme.positive
        case .failed: return WidgetTheme.negative
        case .refunded, .partiallyRefunded: return WidgetTheme.warning
        case .trackingEnded: return WidgetTheme.secondaryText
        default: return WidgetTheme.activityAccent
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if animates {
                // A finite pulse follows fresh observations; it does not imply
                // that the suspended app is still polling in the background.
                Image(systemName: symbolName)
                    .symbolEffect(.pulse, options: .nonRepeating.speed(2), value: state.observedAt)
            } else {
                Image(systemName: symbolName)
            }
            if showsText { Text(LocalizedStringKey(state.phase.localizationKey)) }
        }
        .font(WidgetTheme.labelFont(size: 11))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusLabel)
    }
}

struct TransactionActivityCard: View {
    let state: TransactionActivityState
    var isStale = false
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
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack(spacing: 8) {
                    TransactionActivityBrand()
                    Spacer(minLength: 4)
                    TransactionActivityStatus(state: state, isStale: isStale)
                }
            }
            hero
            if showsDetails { receiptDetails }
            freshness
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hero: some View {
        HStack(spacing: 10) {
            if state.summary != nil {
                HStack(spacing: -8) {
                    tokenAvatar(state.sourceAssetID, size: state.operation == .swap ? 34 : 40)
                    if state.operation == .swap {
                        tokenAvatar(state.destinationAssetID, size: 34)
                    }
                }
                .accessibilityHidden(true)
            } else {
                Image(systemName: "lock.shield")
                    .font(WidgetTheme.iconFont(size: 20))
                    .foregroundStyle(WidgetTheme.activityAccent)
                    .frame(width: 40, height: 40)
                    .background(WidgetTheme.activitySurface, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let operation = state.operation {
                    Text(LocalizedStringKey(operation == .swap ? "transactionActivitySwap" : "transactionActivitySending"))
                        .font(WidgetTheme.labelFont(size: 10))
                        .foregroundStyle(WidgetTheme.secondaryText)
                }
                if let summary = state.summary {
                    Text(summary)
                        .font(WidgetTheme.priceFont(size: 23))
                } else {
                    Text("transactionActivityTitle")
                        .font(WidgetTheme.labelFont(size: 19))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40)
    }

    private func tokenAvatar(_ assetID: String?, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(WidgetTheme.activitySurface)
            if let safeID = TransactionActivityState.bundledAssetID(for: assetID),
               let image = VultisigImage(rawValue: safeID) {
                image.image.resizable().scaledToFit()
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

    private var receiptDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            if state.network != nil || state.recipient != nil {
                HStack(spacing: 6) {
                    if let network = state.network { Text(network) }
                    if let recipient = state.recipient { Label(recipient, systemImage: "arrow.up.right") }
                }
            }
            if state.provider != nil || state.fee != nil {
                HStack(spacing: 6) {
                    if let provider = state.provider { Text(provider) }
                    if let fee = state.fee {
                        Text("transactionActivityFee")
                        Text(fee).layoutPriority(1)
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .font(WidgetTheme.labelFont(size: 10))
        .foregroundStyle(WidgetTheme.secondaryText)
    }

    private var freshness: some View {
        HStack(spacing: 4) {
            if (isStale || state.updateDelayed) && !state.phase.isTerminal {
                Text("transactionActivityDelayed")
                Spacer(minLength: 4)
            } else if let submittedAt = state.submittedAt, !state.phase.isTerminal {
                Text("transactionActivitySubmitted")
                Text(submittedAt, style: .time)
                Spacer(minLength: 4)
            }
            Text("transactionActivityUpdated")
            Text(state.observedAt, style: .time)
                .layoutPriority(1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .font(WidgetTheme.labelFont(size: 10))
        .foregroundStyle(WidgetTheme.tertiaryText)
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
            sourceAssetID: "usdc", destinationAssetID: swap ? "eth" : nil
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

#Preview("Delayed", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
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
