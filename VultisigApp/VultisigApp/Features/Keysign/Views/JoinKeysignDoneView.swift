//
//  JoinKeysignDoneView.swift
//  VultisigApp
//
//  Cosigner-side "done" surface inside `KeysignView`. Dispatches
//  among three branches:
//  - dApp custom-message signing → `KeysignSignedMessageDoneView`
//    (its own done flow — not a tx broadcast).
//  - Swap → unified `DoneScreen` + `SwapDoneSummaryCard.cosigner`,
//    with a `StaticStatusSource` (the peer has no broadcast-side
//    identity to drive a live poller).
//  - Send (default) → unified `DoneScreen` with the default slots,
//    built from the `KeysignPayload` exactly like the initiator
//    builds it from `SendTransaction`.
//

import SwiftData
import SwiftUI

struct JoinKeysignDoneView: View {
    let vault: Vault
    @ObservedObject var viewModel: KeysignViewModel
    @Binding var showAlert: Bool

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    private let summaryViewModel = JoinKeysignSummaryViewModel()
    @StateObject private var statusSource = StaticStatusSource(status: .confirmed)

    @Environment(\.openURL) var openURL
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        VStack(spacing: 32) {
            content
        }
        .redacted(reason: viewModel.showRedacted ? .placeholder : [])
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.customMessagePayload != nil {
            KeysignSignedMessageDoneView(viewModel: viewModel)
        } else if let keysignPayload = viewModel.keysignPayload,
                  keysignPayload.swapPayload != nil,
                  !isLPOperation(memo: keysignPayload.memo) {
            swapBranch(keysignPayload: keysignPayload)
        } else if let keysignPayload = viewModel.keysignPayload {
            sendBranch(keysignPayload: keysignPayload)
        }
    }

    /// Heuristic: LP add/withdraw memos start with `+:` / `-:`. These
    /// ride through the Send done branch even though they carry a
    /// `swapPayload` (the swap fields are for the LP pool, not a
    /// user-facing from/to display).
    private func isLPOperation(memo: String?) -> Bool {
        guard let memo else { return false }
        return memo.starts(with: "+:") || memo.starts(with: "-:")
    }

    @ViewBuilder
    private func sendBranch(keysignPayload: KeysignPayload) -> some View {
        let fees = viewModel.getCalculatedNetworkFee()
        DoneScreen(
            input: TransactionDonePayload(
                coin: keysignPayload.coin,
                amountCrypto: keysignPayload.toAmountWithTickerString,
                amountFiat: keysignPayload.toSendAmountFiatString,
                hero: viewModel.heroContent,
                hash: viewModel.txid,
                explorerLink: viewModel.getTransactionExplorerURL(txid: viewModel.txid),
                memo: viewModel.memo ?? "",
                isSend: true,
                fromAddress: keysignPayload.coin.address,
                toAddress: keysignPayload.toAddress,
                toAlias: SendAddressResolver.resolveAlias(
                    address: keysignPayload.toAddress,
                    coinMeta: keysignPayload.coin.toCoinMeta(),
                    ensLabel: nil,
                    vaults: vaults,
                    addressBookItems: addressBookItems
                ),
                fee: FeeDisplay(crypto: fees.feeCrypto, fiat: fees.feeFiat),
                keysignPayload: keysignPayload,
                pubKeyECDSA: vault.pubKeyECDSA,
                dappMetadata: viewModel.dappMetadata
            ),
            statusSource: statusSource,
            showAlert: $showAlert
        )
    }

    @ViewBuilder
    private func swapBranch(keysignPayload: KeysignPayload) -> some View {
        DoneScreen(
            input: TransactionDonePayload(
                coin: keysignPayload.coin,
                amountCrypto: keysignPayload.toAmountWithTickerString,
                amountFiat: keysignPayload.toSendAmountFiatString,
                hero: viewModel.heroContent,
                hash: viewModel.txid,
                explorerLink: viewModel.getTransactionExplorerURL(txid: viewModel.txid),
                memo: viewModel.memo ?? "",
                isSend: false,
                fromAddress: keysignPayload.coin.address,
                toAddress: keysignPayload.toAddress,
                fee: FeeDisplay(crypto: "", fiat: ""),
                keysignPayload: keysignPayload,
                pubKeyECDSA: vault.pubKeyECDSA,
                dappMetadata: viewModel.dappMetadata
            ),
            statusSource: statusSource,
            showAlert: $showAlert,
            tokenContent: {
                SwapDoneSummaryCard.cosigner(
                    keysignPayload: keysignPayload,
                    vault: vault,
                    summaryViewModel: summaryViewModel,
                    txHash: viewModel.txid,
                    networkFee: viewModel.getCalculatedNetworkFee().feeCrypto,
                    showAlert: $showAlert
                )
            },
            detailContent: {
                EmptyView()
            },
            bottomBarContent: {
                HStack(spacing: 8) {
                    if let progressLink = viewModel.getSwapProgressURL(txid: viewModel.txid) {
                        PrimaryButton(title: "track", type: .secondary) {
                            openTrackLink(progressLink: progressLink, fallbackTxid: viewModel.txid)
                        }
                    } else {
                        PrimaryButton(title: "track", type: .secondary) {
                            openTrackLink(progressLink: nil, fallbackTxid: viewModel.txid)
                        }
                    }
                    PrimaryButton(title: "done") {
                        appViewModel.restart()
                    }
                }
            }
        )
    }

    private func openTrackLink(progressLink: String?, fallbackTxid: String) {
        if let link = progressLink, !link.isEmpty, let url = URL(string: link) {
            openURL(url)
            return
        }
        let urlString = viewModel.getTransactionExplorerURL(txid: fallbackTxid)
        if !urlString.isEmpty, let url = URL(string: urlString) {
            openURL(url)
        }
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneView(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
    .environmentObject(AppViewModel())
}
