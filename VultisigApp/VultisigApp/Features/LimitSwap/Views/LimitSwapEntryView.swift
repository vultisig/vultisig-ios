//
//  LimitSwapEntryView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Wrapper that owns the `LimitSwapFormViewModel` lifecycle plus Limit's
/// **independent** coin selection state. The initial from/to coins seed
/// from the host's selected coins for convenience but subsequent picker
/// changes stay local — they do not mutate the Market path's state.
///
/// On "Place Order" / confirmation success, this view assembles the
/// limit-swap `KeysignPayload` and navigates to `SwapRoute.limitPair(...)`,
/// joining the limit-side pair → keysign → done pipeline managed by
/// `SwapRouter`.
struct LimitSwapEntryView: View {

    let initialFromCoin: Coin
    let initialToCoin: Coin
    let vault: Vault

    @Environment(\.router) private var router

    /// Constructed eagerly in `init` from `initialFromCoin` / `initialToCoin`
    /// so the VM is non-optional throughout the view's lifetime.
    @State private var vm: LimitSwapFormViewModel

    // Independent coin state. Picker bindings (see `pickerBinding(for:)`)
    // intercept selections to swap sides when the user picks the *other*
    // currently-selected coin (i.e. picking ETH on the from-side when the
    // to-side is already ETH inverts the pair instead of producing a
    // self-pair). An onChange syncs each side into the VM's draft.
    @State private var limitFromCoin: Coin
    @State private var limitToCoin: Coin

    @State private var showFromCoinPicker: Bool = false
    @State private var showToCoinPicker: Bool = false

    @State private var confirmationVM: LimitSwapConfirmationViewModel?
    @State private var isConfirmationSheetPresented: Bool = false

    /// `SwapCoinPickerView` declares an `@EnvironmentObject` for this VM and
    /// will crash at runtime if the picker sheet renders without it. The
    /// Market path injects it explicitly on its picker sheet too.
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel

    init(
        initialFromCoin: Coin,
        initialToCoin: Coin,
        vault: Vault
    ) {
        self.initialFromCoin = initialFromCoin
        self.initialToCoin = initialToCoin
        self.vault = vault
        self._limitFromCoin = State(initialValue: initialFromCoin)
        self._limitToCoin = State(initialValue: initialToCoin)

        let draft = LimitSwapDraft(
            fromAsset: LimitSwapAsset(coin: initialFromCoin),
            toAsset: LimitSwapAsset(coin: initialToCoin)
        )
        let interactor = DefaultLimitSwapInteractor(
            quoteService: ThorchainService.shared,
            storage: LimitOrderStorageService()
        )
        let model = LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
        model.targetUsdPricePerUnit = Decimal(initialToCoin.price)
        self._vm = State(initialValue: model)
    }

    var body: some View {
        LimitSwapBodyView(
            vm: vm,
            fromCoin: limitFromCoin,
            toCoin: limitToCoin,
            onPickFromAsset: { showFromCoinPicker = true },
            onPickToAsset: { showToCoinPicker = true },
            onSwapAssets: handleSwapAssets,
            onPlaceOrder: handlePlaceOrder
        )
        .task {
            // Initial setup: kick the supported-chains fetch in parallel
            // (filters the picker so the user can't pick a chain THORChain
            // doesn't route), then seed the market price. `.task` is the
            // right modifier for async work tied to view lifetime — SwiftUI
            // cancels the work if the view leaves the hierarchy.
            async let supportedChains: () = vm.refreshSupportedChains()
            async let marketPrice: () = vm.refreshMarketPrice()
            _ = await (supportedChains, marketPrice)
            vm.selectPresetPct(0)
        }
        .onChange(of: limitFromCoin) { _, newCoin in
            vm.selectFromAsset(LimitSwapAsset(coin: newCoin))
            Task { @MainActor in
                await vm.refreshMarketPrice()
                vm.selectPresetPct(0)
            }
        }
        .onChange(of: limitToCoin) { _, newCoin in
            vm.selectToAsset(LimitSwapAsset(coin: newCoin))
            vm.targetUsdPricePerUnit = Decimal(newCoin.price)
            Task { @MainActor in
                await vm.refreshMarketPrice()
                vm.selectPresetPct(0)
            }
        }
        .crossPlatformSheet(isPresented: $showFromCoinPicker) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $showFromCoinPicker,
                selectedCoin: pickerBinding(for: .from),
                selectedChain: limitFromCoin.chain,
                chainFilter: chainIsThorchainRoutable
            )
            .environmentObject(coinSelectionViewModel)
        }
        .crossPlatformSheet(isPresented: $showToCoinPicker) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $showToCoinPicker,
                selectedCoin: pickerBinding(for: .to),
                selectedChain: limitToCoin.chain,
                chainFilter: chainIsThorchainRoutable
            )
            .environmentObject(coinSelectionViewModel)
        }
        .sheet(isPresented: $isConfirmationSheetPresented) {
            if let confirmationVM {
                LimitSwapConfirmationSheet(
                    vm: confirmationVM,
                    onDismiss: { isConfirmationSheetPresented = false },
                    onSignAttempt: handleSignAttempt
                )
            }
        }
    }

    // MARK: - Picker bindings (swap-on-collision)

    private enum PickerSide { case from, to }

    /// When the user picks a coin on one side that equals the *other* side's
    /// current coin, swap their positions instead of producing a self-pair.
    /// Compares by chain + ticker + contract since `Coin` is a SwiftData
    /// `@Model` (reference identity wouldn't match across picker/vault
    /// instances of the same logical asset).
    private func pickerBinding(for side: PickerSide) -> Binding<Coin> {
        switch side {
        case .from:
            return Binding(
                get: { limitFromCoin },
                set: { newCoin in
                    if sameCoin(newCoin, limitToCoin) {
                        limitToCoin = limitFromCoin
                    }
                    limitFromCoin = newCoin
                }
            )
        case .to:
            return Binding(
                get: { limitToCoin },
                set: { newCoin in
                    if sameCoin(newCoin, limitFromCoin) {
                        limitFromCoin = limitToCoin
                    }
                    limitToCoin = newCoin
                }
            )
        }
    }

    private func sameCoin(_ a: Coin, _ b: Coin) -> Bool {
        a.chain == b.chain
            && a.ticker == b.ticker
            && a.contractAddress == b.contractAddress
    }

    /// Picker chain filter — uses the live set from `vm.supportedChains`
    /// when populated, otherwise falls back to the static prefix-table
    /// check so the picker never opens with a stale unfiltered list during
    /// the brief window before the inbound fetch resolves.
    private func chainIsThorchainRoutable(_ chain: Chain) -> Bool {
        if let supported = vm.supportedChains {
            return supported.contains(chain)
        }
        return isThorchainRoutable(chain: chain)
    }

    // MARK: - Place flow

    private func handlePlaceOrder() {
        guard let fromMemo = vm.draft.fromAsset.memoSymbol,
              let toMemo = vm.draft.toAsset.memoSymbol,
              let destAddress = vm.destinationAddress(),
              vm.draft.sourceAmount > 0,
              vm.draft.targetPrice > 0
        else {
            return
        }

        // Real affiliate config: read the vault's referral code (if any)
        // and compute the affiliate fragment via the same helper the market
        // path uses. Vault-tier discount defaults to 0 for Phase 1; the
        // tier-discount lookup ride-along arrives in a follow-up.
        let referralCode = vault.referralCode?.code ?? ""
        let (affiliate, affiliateBps) = ThorchainService.affiliateParams(
            referredCode: referralCode,
            discountBps: 0
        )

        let inputs = LimitSwapInputs(
            sourceAsset: fromMemo,
            sourceAmount: vm.draft.sourceAmount,
            sourceDecimals: vm.draft.fromAsset.decimals,
            targetAsset: toMemo,
            destAddress: destAddress,
            targetPrice: vm.draft.targetPrice,
            expiryHours: vm.draft.expiryHours,
            affiliate: affiliate ?? THORChainSwaps.affiliateFeeAddress,
            affiliateBps: affiliateBps ?? String(THORChainSwaps.affiliateFeeRateBp)
        )

        let memo = buildLimitSwapMemo(inputs)
        let chainKind = vm.draft.fromAsset.chain.chainType

        confirmationVM = LimitSwapConfirmationViewModel(
            draft: vm.draft,
            memo: memo,
            sourceChainKind: chainKind
        )
        isConfirmationSheetPresented = true
    }

    private func handleSwapAssets() {
        let oldFrom = limitFromCoin
        limitFromCoin = limitToCoin
        limitToCoin = oldFrom
        // onChange handlers will sync the new coins into the VM via
        // selectFromAsset/selectToAsset.
    }

    private func handleSignAttempt() async {
        guard let confirmationVM else { return }

        let fromCoin = limitFromCoin
        let toCoin = limitToCoin
        let vaultRef = vault
        let memo = confirmationVM.memo
        let sourceAmount = vm.draft.sourceAmount
        let draft = vm.draft
        // Capture the destination address up front so it can't drift mid-task
        // (e.g. if the user navigates and the VM gets a different toAsset).
        // Same lookup the inputs build used; mirroring it into the persisted
        // record ensures TX History shows the correct recipient.
        let capturedDestAddress = vm.destinationAddress() ?? ""

        await confirmationVM.attemptSign {
            // Assemble the KeysignPayload for the source chain (fetches
            // THORChain inbound + chain-specific + builds via the existing
            // KeysignPayloadFactory). On any failure, surface to the
            // confirmation VM's error state via throw — attemptSign swallows
            // non-byte-cap errors silently for now (richer error UI can land
            // in a follow-up).
            let payload = try await buildLimitSwapKeysignPayload(
                sourceCoin: fromCoin,
                targetCoin: toCoin,
                sourceAmount: sourceAmount,
                memo: memo,
                vault: vaultRef
            )

            let record = LimitOrderRecord(
                inboundTxHash: "",  // Filled in by the parent after broadcast.
                sourceAsset: draft.fromAsset.memoSymbol ?? "",
                sourceAmount: sourceAmount.description,
                sourceDecimals: draft.fromAsset.decimals,
                targetAsset: draft.toAsset.memoSymbol ?? "",
                destAddress: capturedDestAddress,
                targetPrice: draft.targetPrice,
                expiryBlocks: computeExpiryBlocks(hours: draft.expiryHours),
                createdAt: Date(),
                status: .pending
            )

            await MainActor.run {
                isConfirmationSheetPresented = false
                router.navigate(to: SwapRoute.limitPair(
                    vaultPubKeyECDSA: vaultRef.pubKeyECDSA,
                    keysignPayload: payload,
                    pendingRecord: record
                ))
            }
        }
    }
}
