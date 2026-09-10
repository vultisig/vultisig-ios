import ActivityKit
import SwiftUI
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
                    Image(systemName: context.state.phase.symbol)
                        .foregroundStyle(WidgetTheme.primaryText)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(LocalizedStringKey(context.state.phase.localizationKey))
                        .font(WidgetTheme.labelFont(size: 12))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TransactionActivityCard(state: context.state, isStale: context.isStale, showsHeader: false)
                }
            } compactLeading: {
                Image(systemName: "arrow.up.right")
                    .accessibilityLabel(Text("transactionActivityTitle"))
            } compactTrailing: {
                Image(systemName: context.isStale && !context.state.phase.isTerminal ? "clock" : context.state.phase.symbol)
                    .accessibilityLabel(Text(LocalizedStringKey(context.isStale && !context.state.phase.isTerminal
                        ? "transactionActivityDelayed" : context.state.phase.localizationKey)))
            } minimal: {
                Image(systemName: context.isStale && !context.state.phase.isTerminal ? "clock" : context.state.phase.symbol)
                    .accessibilityLabel(Text(LocalizedStringKey(context.isStale && !context.state.phase.isTerminal
                        ? "transactionActivityDelayed" : context.state.phase.localizationKey)))
            }
            .widgetURL(TransactionActivityLink.url(recordID: context.attributes.recordID))
        }
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
        .frame(maxHeight: 128)
        .foregroundStyle(WidgetTheme.primaryText)
        .accessibilityElement(children: .combine)
    }

    private func card(showsDetails: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader { header }
            if let summary = state.summary {
                Text(summary)
                    .font(WidgetTheme.priceFont(size: 20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if showsDetails { receiptDetails }
            freshness
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack {
            Text(LocalizedStringKey(state.operation.map {
                $0 == .swap ? "transactionActivitySwap" : "transactionActivitySending"
            } ?? "transactionActivityTitle"))
            Spacer(minLength: 8)
            Label(LocalizedStringKey(state.phase.localizationKey), systemImage: state.phase.symbol)
        }
        .lineLimit(1)
        .font(WidgetTheme.labelFont(size: 12))
        .foregroundStyle(WidgetTheme.secondaryText)
    }

    private var receiptDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.network != nil || state.recipient != nil {
                HStack {
                    if let network = state.network { Text(network) }
                    if let recipient = state.recipient { Label(recipient, systemImage: "arrow.up.right") }
                }
            }
            if state.provider != nil || state.fee != nil {
                HStack {
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
        .font(WidgetTheme.labelFont(size: 11))
        .foregroundStyle(WidgetTheme.secondaryText)
    }

    private var freshness: some View {
        VStack(alignment: .leading, spacing: 2) {
            if (isStale || state.updateDelayed) && !state.phase.isTerminal {
                Label("transactionActivityDelayed", systemImage: "clock")
            } else if let submittedAt = state.submittedAt, !state.phase.isTerminal {
                HStack {
                    Text("transactionActivitySubmitted")
                    Text(submittedAt, style: .relative)
                }
            }
            HStack {
                Text("transactionActivityUpdated")
                Text(state.observedAt, style: .time)
            }
        }
        .lineLimit(1)
        .font(WidgetTheme.labelFont(size: 11))
        .foregroundStyle(WidgetTheme.secondaryText)
    }
}

#if DEBUG
#Preview("Transfer", as: .content, using: TransactionActivityAttributes(recordID: UUID())) {
    TransactionLiveActivityWidget()
} contentStates: {
    TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                             summary: "125 USDC", network: "Base", showDetails: true)
    TransactionActivityState(phase: .swapping, observedAt: Date(), revision: 2,
                             summary: "125 USDC → ETH", network: "Base", showDetails: true)
    TransactionActivityState(phase: .pending, observedAt: Date(), revision: 3, updateDelayed: true)
}
#endif
