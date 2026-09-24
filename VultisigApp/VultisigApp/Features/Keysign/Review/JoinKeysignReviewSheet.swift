//
//  JoinKeysignReviewSheet.swift
//  VultisigApp
//
//  The co-signer's payload-backed review. Join owns the signing ceremony;
//  this sheet only presents the received transaction and requests a join.
//

import SwiftUI

struct JoinKeysignReviewSheet: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    @Binding var presentedKind: JoinKeysignReviewPresentation.Kind?
    let kind: JoinKeysignReviewPresentation.Kind

    @State private var showsRiskVerdict = false

    var body: some View {
        KeysignReviewSheet(
            title: kind == .swap ? "swapOverview".localized : "sendOverview".localized,
            scanRing: KeysignReviewScanRing(
                viewModel.securityScannerState,
                isScanComplete: viewModel.didLoadSimulation
            ),
            verdict: verdict,
            onClose: { presentedKind = nil },
            content: {
                switch kind {
                case .send:
                    SendReviewSummaryView(input: JoinKeysignReviewPresentation.sendSummary(viewModel: viewModel))
                case .swap:
                    if let summary = JoinKeysignReviewPresentation.swapSummary(viewModel: viewModel) {
                        SwapReviewSummaryView(summary: summary)
                    }
                }
            },
            footer: { footer }
        )
        .task {
            async let thor: Void = viewModel.loadThorchainID()
            async let function: Void = viewModel.loadFunctionName()
            async let simulation: Void = viewModel.loadSimulation()
            async let resolved: Void = viewModel.loadResolvedHero()
            _ = await (thor, function, simulation, resolved)
        }
    }

    private var verdict: KeysignReviewVerdict? {
        guard showsRiskVerdict, let result = viewModel.securityScannerState.result else { return nil }
        return KeysignReviewVerdict(
            result: result,
            onGoBack: { showsRiskVerdict = false },
            onContinueAnyway: {
                showsRiskVerdict = false
                viewModel.joinKeysignCommittee()
            }
        )
    }

    private var footer: some View {
        VStack(spacing: 16) {
            if kind == .send,
               let message = SubstrateAllowDeathDisclosure.message(for: viewModel.keysignPayload) {
                InfoBannerView(description: message, type: .warning, leadingIcon: .triangleWarning)
            }

            if kind == .send,
               LimitOrderCancelPresentation.isCancel(memo: viewModel.keysignPayload?.memo) {
                Text("limitSwap.cancel.explanation".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.solanaAtaRentState == .failed {
                InfoBannerView(
                    description: "errorNetworkUnstableDescription".localized,
                    type: .warning,
                    leadingIcon: .triangleWarning
                )
                PrimaryButton(title: "retry") {
                    viewModel.retrySolanaAtaRentLookup()
                }
            }

            PrimaryButton(title: "joinTransactionSigning", isLoading: viewModel.isJoiningCommittee) {
                join()
            }
            .disabled(
                viewModel.isJoiningCommittee
                    || viewModel.isKaminoDecodeRefused
                    || !viewModel.isSolanaFeeReady
                    || !viewModel.didLoadSimulation
            )
        }
    }

    private func join() {
        guard !viewModel.isJoiningCommittee,
              !viewModel.isKaminoDecodeRefused,
              viewModel.isSolanaFeeReady,
              viewModel.didLoadSimulation else { return }
        if let result = viewModel.securityScannerState.result, !result.isSecure {
            showsRiskVerdict = true
        } else {
            viewModel.joinKeysignCommittee()
        }
    }
}
