//
//  SwapCryptoView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SwapCryptoView: View {
    let fromCoin: Coin?
    let toCoin: Coin?
    let vault: Vault

    @State var keysignView: KeysignView?

    @StateObject var tx = SwapTransaction()
    @StateObject var swapViewModel = SwapCryptoViewModel()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()

    @State private var selectedSwapMode: SwapMode = .market
    @State private var isLimitSwapFeatureEnabled = false
    /// Set when the user signs a limit order; `swapViewModel.hash` flipping
    /// non-empty (broadcast success) triggers a persist via
    /// `LimitOrderStorageService` then clears this. Nil during market-swap
    /// flows so the existing path is unaffected.
    @State private var pendingLimitOrderRecord: LimitOrderRecord?

    init(fromCoin: Coin? = nil, toCoin: Coin? = nil, vault: Vault) {
        self.fromCoin = fromCoin
        self.toCoin = toCoin
        self.vault = vault
    }

    var body: some View {
        content
            .onLoad {
                if let fromCoin {
                    tx.fromCoin = fromCoin
                }
            }
            .onChange(of: swapViewModel.pendingRetryReason) { _, reason in
                guard reason != nil else { return }
                keysignView = nil
                swapViewModel.stopMediator()
            }
            .task {
                // Feature-flag fetch. Default false keeps the tab hidden and
                // the market-swap path pixel-identical when the flag is off.
                isLimitSwapFeatureEnabled = true

//                await FeatureFlagService()
//                    .isFeatureEnabled(feature: .limitSwap)
            }
            .onChange(of: swapViewModel.hash) { _, newHash in
                persistLimitOrderIfNeeded(hash: newHash)
            }
    }

    var view: some View {
        VStack(spacing: 18) {
            tabView
        }
    }

    @ViewBuilder
    var tabView: some View {
        ZStack {
            switch swapViewModel.currentIndex {
            case 1:
                detailsView
            case 2:
                verifyView
            case 3:
                pairView
            case 4:
                keysign
            case 5:
                doneView
            default:
                errorView
            }
        }
    }

    @ViewBuilder
    var detailsView: some View {
        if isLimitSwapFeatureEnabled {
            VStack(alignment: .leading, spacing: 0) {
                SegmentedControl(
                    selection: $selectedSwapMode,
                    items: [
                        SegmentedControlItem(
                            value: .market,
                            title: "swap.tab.market".localized
                        ),
                        SegmentedControlItem(
                            value: .limit,
                            title: "swap.tab.limit".localized,
                            isEnabled: canCurrentPairUseLimitSwap
                        )
                    ]
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .fixedSize()

                switch selectedSwapMode {
                case .market:
                    SwapCryptoDetailsView(tx: tx, swapViewModel: swapViewModel, vault: vault)
                case .limit:
                    LimitSwapEntryView(
                        initialFromCoin: tx.fromCoin,
                        initialToCoin: tx.toCoin,
                        vault: vault,
                        onLimitPayloadReady: handleLimitPayloadReady
                    )
                }
            }
        } else {
            // Flag off: market path is pixel-identical to pre-feature.
            SwapCryptoDetailsView(tx: tx, swapViewModel: swapViewModel, vault: vault)
        }
    }

    /// Receives the assembled KeysignPayload from the Limit flow's
    /// confirmation sheet, populates the existing `tx` + `swapViewModel` so
    /// the existing pair → keysign → done state machine renders correctly,
    /// and stashes the pending order record for persist-on-broadcast-success
    /// (handled by the `swapViewModel.hash` onChange below).
    private func handleLimitPayloadReady(_ context: LimitSwapSignContext) {
        // Mirror limit data into the SwapTransaction so KeysignDiscoveryView
        // / KeysignView / SendCryptoDoneView render correct chain + amounts.
        tx.fromCoin = context.fromCoin
        tx.toCoin = context.toCoin
        tx.fromAmount = context.sourceAmountText

        swapViewModel.keysignPayload = context.payload
        // Skip the verify view (we already showed the confirmation sheet) by
        // advancing the state machine twice: 1 (details) → 2 (verify) → 3
        // (pair). `moveToNextView` keeps the navigation title in sync; we
        // use the public method rather than touching the private titles array.
        swapViewModel.moveToNextView()
        swapViewModel.moveToNextView()

        pendingLimitOrderRecord = context.pendingRecord
    }

    /// Persist the limit order on broadcast success. `swapViewModel.hash`
    /// flips to a non-empty inbound TX hash when broadcast lands; we splice
    /// that hash into the pending record and call the storage service. Do
    /// not persist on broadcast failure (per design.md — no ghost orders).
    private func persistLimitOrderIfNeeded(hash: String?) {
        guard let hash, !hash.isEmpty,
              let record = pendingLimitOrderRecord else { return }

        let updated = LimitOrderRecord(
            inboundTxHash: hash,
            sourceAsset: record.sourceAsset,
            sourceAmount: record.sourceAmount,
            sourceDecimals: record.sourceDecimals,
            targetAsset: record.targetAsset,
            destAddress: record.destAddress,
            targetPrice: record.targetPrice,
            expiryBlocks: record.expiryBlocks,
            createdAt: record.createdAt,
            status: record.status
        )

        let storage = LimitOrderStorageService()
        do {
            try storage.persist(updated, for: vault)
        } catch {
            // Persist failure is non-fatal: the broadcast already succeeded.
            // Log and drop — the user still sees the success screen with the
            // inbound TX hash, and TX History will pick up the inbound TX.
        }
        pendingLimitOrderRecord = nil
    }

    private var canCurrentPairUseLimitSwap: Bool {
        func hasThorchainProvider(_ providers: [SwapProvider]) -> Bool {
            providers.contains { provider in
                switch provider {
                case .thorchain, .thorchainChainnet, .thorchainStagenet:
                    return true
                default:
                    return false
                }
            }
        }
        return hasThorchainProvider(tx.fromCoin.swapProviders)
            && hasThorchainProvider(tx.toCoin.swapProviders)
    }

    var verifyView: some View {
        SwapVerifyView(tx: tx, swapViewModel: swapViewModel, vault: vault)
    }

    var pairView: some View {
        ZStack {
            if let keysignPayload = swapViewModel.keysignPayload {
                KeysignDiscoveryView(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    customMessagePayload: nil,
                    fastVaultPassword: tx.fastVaultPassword.nilIfEmpty,
                    shareSheetViewModel: shareSheetViewModel,
                    previewType: .Swap,
                    swapTransaction: tx
                ) { input in
                    self.keysignView = KeysignView(
                        vault: input.vault,
                        keysignCommittee: input.keysignCommittee,
                        mediatorURL: input.mediatorURL,
                        sessionID: input.sessionID,
                        keysignType: input.keysignType,
                        messsageToSign: input.messsageToSign,
                        keysignPayload: input.keysignPayload,
                        customMessagePayload: input.customMessagePayload,
                        transferViewModel: swapViewModel,
                        encryptionKeyHex: input.encryptionKeyHex,
                        isInitiateDevice: input.isInitiateDevice
                    )
                    swapViewModel.moveToNextView()
                }
            } else {
                SendCryptoVaultErrorView()
            }
        }
    }

    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                SendCryptoSigningErrorView(errorString: swapViewModel.error?.localizedDescription ?? "Error")
            }
        }
    }

    var doneView: some View {
        ZStack {
            if let hash = swapViewModel.hash {
                SendCryptoDoneView(
                    vault: vault, hash: hash, approveHash: swapViewModel.approveHash,
                    chain: tx.fromCoin.chain,
                    progressLink: swapViewModel.progressLink(tx: tx, hash: hash),
                    sendTransaction: nil,
                    swapTransaction: tx,
                    isSend: false
                )
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            } else {
                SendCryptoSigningErrorView(errorString: swapViewModel.error?.localizedDescription ?? "Error")
            }
        }.onAppear {
            Task {
                try? await Task.sleep(for: .seconds(5))
                swapViewModel.stopMediator()
            }
        }
    }

    var errorView: some View {
        SendCryptoSigningErrorView(errorString: swapViewModel.error?.localizedDescription ?? "Error")
    }

    var showBackButton: Bool {
        swapViewModel.currentIndex != 1 && swapViewModel.currentIndex != 5
    }

    var backButton: some View {
        return Button {
            swapViewModel.handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
    }
}

#Preview {
    SwapCryptoView(vault: .example)
}

#if os(iOS)
import SwiftUI

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onLoad {
            UIApplication.shared.isIdleTimerDisabled = true
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
        .navigationTitle(NSLocalizedString(swapViewModel.currentTitle, comment: "SendCryptoView title"))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .toolbar {
            if showBackButton {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    backButton
                }
            }

            if swapViewModel.currentIndex==3 {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                    NavigationQRShareButton(
                        vault: vault,
                        type: .Keysign,
                        viewModel: shareSheetViewModel
                    )
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    var main: some View {
        views
    }

    var views: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

extension SwapCryptoView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .onLoad {
            swapViewModel.load(initialFromCoin: fromCoin, initialToCoin: toCoin, vault: vault, tx: tx)
        }
        .task {
            await swapViewModel.loadFastVault(tx: tx, vault: vault)
        }
        .navigationBarBackButtonHidden(swapViewModel.currentIndex != 1 ? true : false)
    }

    var main: some View {
        VStack {
            headerMac
            views
        }
    }

    var headerMac: some View {
        SwapCryptoHeader(
            vault: vault,
            swapViewModel: swapViewModel,
            shareSheetViewModel: shareSheetViewModel
        )
    }

    var views: some View {
        ZStack {
            Background()
            view
        }
        .onDisappear {
            swapViewModel.stopMediator()
        }
    }
}
#endif
