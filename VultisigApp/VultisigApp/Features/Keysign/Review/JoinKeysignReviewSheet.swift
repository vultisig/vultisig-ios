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

    @State private var showsScanStatus = false

    var body: some View {
        KeysignReviewSheet(
            title: kind.title,
            scanRing: KeysignReviewScanRing(
                viewModel.securityScannerState,
                isScanComplete: viewModel.didLoadSimulation
            ),
            scanStatus: scanStatus,
            onClose: { presentedKind = nil },
            onTapScanMark: revealScanStatus,
            content: {
                if let summary = JoinKeysignReviewPresentation.summary(for: kind, viewModel: viewModel) {
                    KeysignReviewSummaryContentView(summary: summary) {
                        if kind == .function,
                           LimitOrderCancelPresentation.isCancel(memo: viewModel.keysignPayload?.memo) {
                            Text("limitSwap.cancel.explanation".localized)
                                .font(Theme.fonts.caption12)
                                .foregroundStyle(Theme.colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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

    private var scanStatus: KeysignReviewScanStatus? {
        .forSecurityScanner(
            showSecurityScannerSheet: showsScanStatus,
            result: viewModel.securityScannerState.result,
            isContinueAnywayDisabled: isJoinDisabled,
            onDismiss: { showsScanStatus = false },
            onContinueAnyway: {
                showsScanStatus = false
                viewModel.joinKeysignCommittee()
            }
        )
    }

    private func revealScanStatus() {
        showsScanStatus = true
    }

    /// The exact predicate the Join button disables on, reused so "Continue
    /// anyway" can never join something Join itself would refuse.
    private var isJoinDisabled: Bool {
        viewModel.isJoiningCommittee
            || viewModel.isKaminoDecodeRefused
            || !viewModel.isSolanaFeeReady
            || !viewModel.didLoadSimulation
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
            .disabled(isJoinDisabled)
        }
    }

    private func join() {
        guard !isJoinDisabled else { return }
        if JoinKeysignReviewPresentation.requiresRiskAcknowledgement(viewModel.securityScannerState) {
            showsScanStatus = true
        } else {
            viewModel.joinKeysignCommittee()
        }
    }
}
