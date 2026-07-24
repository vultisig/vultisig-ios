//
//  JoinKeysignDoneView.swift
//  VultisigApp
//
//  Cosigner-side "done" surface inside `KeysignView`. Three branches,
//  all of which render the unified `DoneScreen` as their root:
//
//  - dApp custom-message signing → `DoneScreen` with the
//    `SignedMessageDoneTokenContent` token slot. Uses the `.sign`
//    verb so the header reads "Message signed" (no chain status to
//    poll).
//  - Swap → `DoneScreen` + `SwapDoneSummaryCard.cosigner` token slot
//    + custom Track / Done bottom bar.
//  - Send (default) → `DoneScreen` with the default slots, built from
//    the `KeysignPayload` exactly like the initiator builds it from
//    `SendTransaction`.
//

import SwiftData
import SwiftUI

struct JoinKeysignDoneView: View {
    let vault: Vault
    @ObservedObject var viewModel: KeysignViewModel

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    private let summaryViewModel = JoinKeysignSummaryViewModel()

    @Environment(\.openURL) var openURL
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        content.redacted(reason: viewModel.showRedacted ? .placeholder : [])
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.customMessagePayload != nil {
            signedMessageBranch
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

    /// Which done-screen vocabulary a memo earns, on a device that has nothing
    /// but the payload to go on.
    ///
    /// The two limit memo types are disjoint prefixes — `=<:` PLACES an order,
    /// `m=<:` modifies one — and they warrant opposite headlines: a placement is
    /// reported in terms of the order (submitted → resting → filled), while a
    /// cancel is reported in terms of the TRANSACTION, because a cancel THORChain
    /// accepts can still match nothing.
    private func doneVerb(for memo: String?) -> TransactionActionVerb {
        if LimitOrderCancelPresentation.isCancel(memo: memo) { return .cancelLimitOrder }
        return isLimitSwapMemo(memo) ? .limitOrder : .send
    }

    @ViewBuilder
    private func sendBranch(keysignPayload: KeysignPayload) -> some View {
        let fees = viewModel.getCalculatedNetworkFee()
        DoneScreen(
            input: TransactionDonePayload(
                coin: keysignPayload.coin,
                amountCrypto: keysignPayload.toAmountWithTickerString,
                amountFiat: keysignPayload.toSendAmountFiatString,
                hero: LimitOrderCancelPresentation.hero(
                    forSignedMemo: keysignPayload.memo
                ) ?? viewModel.heroContent,
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
                // A NATIVE-source limit order carries no swap payload, so it
                // lands on the Send branch. Without the verb the header would
                // call a resting order a completed transaction — the same lie
                // the initiator screen fixes, just on the peer device. A CANCEL
                // (`m=<`) is a different memo type and a different claim: what
                // succeeded is the transaction, not the closing of the order.
                verb: doneVerb(for: keysignPayload.memo),
                dappMetadata: viewModel.dappMetadata
            ),
            statusService: DoneStatusServiceFactory.cosigner(
                keysignPayload: keysignPayload,
                txHash: viewModel.txid,
                vault: vault
            )
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
                // An ERC20-source limit order rides a swap payload (for the
                // router's `depositWithExpiry`) and so lands here.
                verb: doneVerb(for: keysignPayload.memo),
                dappMetadata: viewModel.dappMetadata
            ),
            statusService: DoneStatusServiceFactory.cosigner(
                keysignPayload: keysignPayload,
                txHash: viewModel.txid,
                vault: vault
            ),
            tokenContent: {
                SwapDoneSummaryCard.cosigner(
                    keysignPayload: keysignPayload,
                    vault: vault,
                    summaryViewModel: summaryViewModel,
                    txHash: viewModel.txid,
                    networkFee: viewModel.getCalculatedNetworkFee().feeCrypto
                )
            },
            detailContent: {
                EmptyView()
            },
            bottomBarContent: {
                HStack(spacing: 8) {
                    PrimaryButton(title: "track", type: .secondary) {
                        openTrackLink(
                            progressLink: viewModel.getSwapProgressURL(txid: viewModel.txid),
                            fallbackTxid: viewModel.txid
                        )
                    }
                    PrimaryButton(title: "done") {
                        appViewModel.restart()
                    }
                }
            }
        )
    }

    /// Synthesizes a `TransactionDonePayload` that drives `DoneScreen`'s
    /// chrome (status header reads "Message signed"; hash/fee/amount
    /// rows are unused — the token slot below renders the real
    /// signed-message detail).
    @ViewBuilder
    private var signedMessageBranch: some View {
        DoneScreen(
            input: TransactionDonePayload(
                coin: .example,
                amountCrypto: "",
                amountFiat: "",
                hash: "",
                explorerLink: "",
                memo: "",
                isSend: false,
                fromAddress: "",
                toAddress: "",
                fee: FeeDisplay(crypto: "", fiat: ""),
                keysignPayload: nil,
                pubKeyECDSA: vault.pubKeyECDSA,
                verb: .sign
            ),
            statusService: DoneStatusServiceFactory.signedMessage(),
            tokenContent: {
                SignedMessageDoneTokenContent(viewModel: viewModel)
            },
            detailContent: {
                EmptyView()
            },
            bottomBarContent: {
                DoneDefaultBottomBar()
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
    JoinKeysignDoneView(vault: Vault.example, viewModel: KeysignViewModel())
        .environmentObject(AppViewModel())
}
