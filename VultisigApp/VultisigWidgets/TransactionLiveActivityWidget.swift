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
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                header
            }

            if let summary = state.summary {
                Text(summary)
                    .font(WidgetTheme.priceFont(size: 20))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            if let network = state.network {
                Text(network).font(WidgetTheme.labelFont(size: 12))
            }
            receiptDetails
        }
        .foregroundStyle(WidgetTheme.primaryText)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack {
                Text(LocalizedStringKey(state.operation.map {
                    $0 == .swap ? "transactionActivitySwap" : "transactionActivitySending"
                } ?? "transactionActivityTitle"))
                Spacer(minLength: 8)
                Label(LocalizedStringKey(state.phase.localizationKey), systemImage: state.phase.symbol)
            }
            .font(WidgetTheme.labelFont(size: 12))
            .foregroundStyle(WidgetTheme.secondaryText)

    }

    private var receiptDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recipient = state.recipient {
                Label(recipient, systemImage: "arrow.up.right")
                    .font(WidgetTheme.labelFont(size: 12))
            }
            if let provider = state.provider {
                Text(provider)
                    .font(WidgetTheme.labelFont(size: 11))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
            }
            if let fee = state.fee {
                HStack {
                    Text("transactionActivityFee")
                    Text(fee).layoutPriority(1)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .font(WidgetTheme.labelFont(size: 11))
                .foregroundStyle(WidgetTheme.secondaryText)
            }
            if let submittedAt = state.submittedAt, !state.phase.isTerminal {
                HStack {
                    Text("transactionActivitySubmitted")
                    Text(submittedAt, style: .relative)
                }
                .font(WidgetTheme.labelFont(size: 11))
                .foregroundStyle(WidgetTheme.secondaryText)
            }
            HStack {
                Text("transactionActivityUpdated")
                Text(state.observedAt, style: .time)
                if (isStale || state.updateDelayed) && !state.phase.isTerminal {
                    Text("transactionActivityDelayed")
                }
            }
            .font(WidgetTheme.labelFont(size: 11))
            .foregroundStyle(WidgetTheme.secondaryText)
        }
        .foregroundStyle(WidgetTheme.primaryText)
        .accessibilityElement(children: .combine)
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
