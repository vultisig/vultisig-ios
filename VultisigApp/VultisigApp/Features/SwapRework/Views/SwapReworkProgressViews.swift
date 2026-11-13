//
//  SwapReworkProgressViews.swift
//  VultisigApp
//
//  After broadcast: the stage tracker (sent, swapped, received, observed and
//  timestamped, never a fake progress bar) and the success summary with the
//  quoted amount against what was delivered.
//

import SwiftUI

struct SwapReworkTrackerView: View {
    let state: SwapReworkTrackerState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            legBar
            VStack(alignment: .leading, spacing: 6) {
                Text("swapReworkYoullReceive".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(state.receiveAmountText)
                    .font(Theme.fonts.priceLargeTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("swapReworkTrackerAmount")
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(phaseColor)
                }
            }
            stagesCard
        }
    }

    private var subtitle: String? {
        switch state.phase {
        case .inProgress: return state.remainingText
        case .takingLonger: return "swapReworkTakingLonger".localized
        case .completed: return "swapReworkArrived".localized
        case .failed: return "swapReworkFailed".localized
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .inProgress, .completed: return Theme.colors.textPrimary
        case .takingLonger: return Theme.colors.alertWarning
        case .failed: return Theme.colors.alertError
        }
    }

    private var legBar: some View {
        HStack(spacing: 8) {
            AsyncImageView(logo: state.pay.logo, size: CGSize(width: 28, height: 28), ticker: state.pay.ticker, tokenChainLogo: state.pay.chainLogo)
            ForEach(state.stages) { stage in
                Capsule()
                    .fill(color(for: stage.status))
                    .frame(height: 4)
            }
            AsyncImageView(logo: state.receive.logo, size: CGSize(width: 28, height: 28), ticker: state.receive.ticker, tokenChainLogo: state.receive.chainLogo)
        }
        .accessibilityHidden(true)
    }

    private var stagesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(state.stages.enumerated()), id: \.element.id) { index, stage in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        indicator(stage.status)
                        if index < state.stages.count - 1 {
                            Rectangle()
                                .fill(stage.status == .done ? Theme.colors.alertSuccess : Theme.colors.borderLight)
                                .frame(width: 2, height: 30)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title(for: stage))
                                .font(Theme.fonts.bodyMMedium)
                                .foregroundStyle(stage.status == .waiting ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                            Spacer(minLength: 8)
                            if let time = state.stageTimes[stage.kind] {
                                Text(time)
                                    .font(Theme.fonts.priceCaption)
                                    .foregroundStyle(Theme.colors.textTertiary)
                            }
                        }
                        Text(detail(for: stage.kind))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let note = state.legNotes[stage.kind] {
                            Text(note)
                                .font(Theme.fonts.caption10)
                                .foregroundStyle(Theme.colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .swapReworkCard(highlighted: false)
    }

    private func indicator(_ status: SwapTrackerStage.Status) -> some View {
        indicatorGlyph(status).frame(width: 24, height: 24)
    }

    @ViewBuilder
    private func indicatorGlyph(_ status: SwapTrackerStage.Status) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.alertSuccess)
        case .active:
            ProgressView()
                .controlSize(.small)
                .tint(Theme.colors.primaryAccent4)
        case .waiting:
            Circle()
                .stroke(Theme.colors.borderLight, lineWidth: 2)
                .frame(width: 20, height: 20)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.alertError)
        }
    }

    private func color(for status: SwapTrackerStage.Status) -> Color {
        switch status {
        case .done: return Theme.colors.alertSuccess
        case .active: return Theme.colors.primaryAccent4
        case .waiting: return Theme.colors.bgSurface2
        case .failed: return Theme.colors.alertError
        }
    }

    /// Past tense once a stage is done, progressive while it runs or waits.
    private func title(for stage: SwapTrackerStage) -> String {
        let done = stage.status == .done
        switch stage.kind {
        case .sent:
            return String(format: (done ? "swapReworkStageSent" : "swapReworkStageSending").localized, state.pay.chainName)
        case .swapped:
            return String(format: (done ? "swapReworkStageSwapped" : "swapReworkStageSwapping").localized, state.providerName)
        case .received:
            return String(format: (done ? "swapReworkStageReceivedDone" : "swapReworkStageReceived").localized, state.receive.chainName)
        }
    }

    private func detail(for kind: SwapTrackerStage.Kind) -> String {
        switch kind {
        case .sent: return state.sentDetail
        case .swapped: return state.swappedDetail
        case .received: return state.receivedDetail
        }
    }
}

struct SwapReworkSuccessView: View {
    let state: SwapReworkSuccessState

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                AsyncImageView(logo: state.receive.logo, size: CGSize(width: 64, height: 64), ticker: state.receive.ticker, tokenChainLogo: state.receive.chainLogo)
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.alertSuccess)
                    .background(Circle().fill(Theme.colors.bgPrimary))
                    .offset(x: 8, y: -6)
            }
            Text(String(format: "swapReworkReceivedIn".localized, state.vaultName))
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(state.deliveredText)
                .font(Theme.fonts.priceLargeTitle)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("swapReworkDelivered")
            Text(state.deliveredFiatText)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textTertiary)

            VStack(spacing: 12) {
                row("swapReworkQuoted".localized, state.quotedText)
                if state.isDeliveredKnown {
                    row("swapReworkDeliveredLabel".localized, String(state.deliveredText.drop(while: { $0 == "+" })), color: Theme.colors.alertSuccess)
                } else {
                    Text((state.isCheckingDelivered ? "swapReworkCheckingDelivered" : "swapReworkDeliveredUnreported").localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let difference = state.differenceText {
                    row(
                        "swapReworkDifference".localized,
                        difference,
                        color: (state.outcome?.isBetterThanQuoted ?? true) ? Theme.colors.alertSuccess : Theme.colors.alertWarning
                    )
                }
            }
            .padding(16)
            .swapReworkCard(highlighted: false)

            VStack(spacing: 12) {
                if let took = state.tookText { row("swapReworkTook".localized, took) }
                row("swapReworkFees".localized, state.feesText)
                if let tier = state.tierName, let saved = state.tierSavedText {
                    row(String(format: "swapReworkTierSaved".localized, tier), saved)
                }
            }
            .padding(16)
            .swapReworkCard(highlighted: false)
        }
    }

    private func row(_ title: String, _ value: String, color: Color = Theme.colors.textPrimary) -> some View {
        HStack {
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Allow + swap, the steps of an ERC-20 swap that needs an approval: what each
/// transaction does, in order, before review.
struct SwapReworkApprovalStepsView: View {
    let approval: SwapReworkApproval
    let receiveTicker: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("swapReworkAllowSwap".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            step(index: 1, title: String(format: "swapReworkStepAllow".localized, approval.amountText, approval.ticker),
                 detail: String(format: "swapReworkStepAllowDetail".localized, approval.spenderName))
            step(index: 2, title: String(format: "swapReworkStepSwap".localized, approval.amountText, approval.ticker, receiveTicker),
                 detail: "swapReworkStepSwapDetail".localized)
            Text("swapReworkStepsFooter".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func step(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(Theme.colors.bgSurface2)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(detail)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "Notify me" under the tracker: off, on (with Undo), or blocked by the OS
/// permission (with a way to the app's notification settings).
struct SwapReworkNotifyCard: View {
    let state: SwapLandingNotifier.State
    let ticker: String
    let onTurnOn: () -> Void
    let onTurnOff: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: state == .on ? "bell.fill" : "bell")
                .foregroundStyle(state == .on ? Theme.colors.alertSuccess : Theme.colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .on {
                    Text("swapReworkNotifyLocalOnly".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Text(actionTitle)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(state == .on ? Theme.colors.alertSuccess : Theme.colors.primaryAccent4)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("swapReworkNotify")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(state == .on ? Theme.colors.alertSuccess.opacity(0.12) : .clear)
        .swapReworkCard(highlighted: false)
    }

    private var message: String {
        switch state {
        case .off: return String(format: "swapReworkNotifyOffBody".localized, ticker)
        case .on: return String(format: "swapReworkNotifyOnBody".localized, ticker)
        case .permissionDenied: return "swapReworkNotifyDeniedBody".localized
        }
    }

    private var actionTitle: String {
        switch state {
        case .off: return "swapReworkNotifyMe".localized
        case .on: return "swapReworkNotifyUndo".localized
        case .permissionDenied: return "swapReworkNotifySettings".localized
        }
    }

    private func action() {
        switch state {
        case .off: onTurnOn()
        case .on: onTurnOff()
        case .permissionDenied: onOpenSettings()
        }
    }
}
