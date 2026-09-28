//
//  WalletConnectPresentationModifier.swift
//  VultisigApp
//

import SwiftUI

struct WalletConnectPresentationModifier: ViewModifier {
    @ObservedObject var coordinator: WalletConnectCoordinator
    @State private var showProposal = false
    @State private var showMessageRequest = false

    func body(content: Content) -> some View {
        content
            .presentsWhenUnlocked(on: coordinator.pendingProposal?.id) {
                showProposal = coordinator.pendingProposal != nil
            }
            .onChange(of: coordinator.pendingProposal?.id) { _, proposalId in
                guard proposalId == nil else { return }
                showProposal = false
            }
            .presentsWhenUnlocked($showProposal)
            .sheet(isPresented: $showProposal) {
                if let proposal = coordinator.pendingProposal {
                    WalletConnectProposalApprovalSheet(
                        proposal: proposal,
                        coordinator: coordinator
                    )
                    .interactiveDismissDisabled()
                }
            }
            .presentsWhenUnlocked(on: coordinator.pendingMessageRequest?.requestId) {
                showMessageRequest = coordinator.pendingMessageRequest != nil
            }
            .onChange(of: coordinator.pendingMessageRequest?.requestId) { _, requestId in
                guard requestId == nil else { return }
                showMessageRequest = false
            }
            .presentsWhenUnlocked($showMessageRequest)
            .sheet(isPresented: $showMessageRequest) {
                if let request = coordinator.pendingMessageRequest {
                    if request.method == "eth_sendTransaction" {
                        WalletConnectTransactionRequestSheet(
                            incomingRequest: request,
                            coordinator: coordinator
                        )
                        .interactiveDismissDisabled()
                    } else {
                        WalletConnectMessageRequestSheet(
                            incomingRequest: request,
                            coordinator: coordinator
                        )
                        .interactiveDismissDisabled()
                    }
                }
            }
    }
}

extension View {
    func walletConnectPresentation(coordinator: WalletConnectCoordinator) -> some View {
        modifier(WalletConnectPresentationModifier(coordinator: coordinator))
    }
}
