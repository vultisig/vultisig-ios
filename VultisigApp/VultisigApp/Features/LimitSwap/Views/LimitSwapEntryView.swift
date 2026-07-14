//
//  LimitSwapEntryView.swift
//  VultisigApp
//

import SwiftUI

/// Wrapper that owns the `LimitSwapFormViewModel` lifecycle plus Limit's
/// **independent** coin selection state. The initial from/to coins seed
/// from the host's selected coins for convenience but subsequent picker
/// changes stay local — they do not mutate the Market path's state.
///
/// "Place Order" assembles the limit memo, runs the byte-cap pre-flight,
/// and routes into the **shared** `SwapRoute.verify(...)` screen with a
/// `SwapTransaction` carrying `limitContext`. From there the standard
/// Swap pipeline (Verify → Pair → Keysign → Done) handles the rest —
/// each screen surfaces limit-specific UI when `transaction.isLimit`.
///
/// **Design-review branch:** this entry view additionally carries all four
/// candidate limit layouts (see `LimitLayoutVariant`) behind a runtime picker.
/// Only the body view swaps — the VM, the coin state, the pickers, the
/// routability gate and the place-order flow below are shared verbatim by every
/// variant, which is what makes the comparison honest.
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

    /// Which candidate layout to render. The picker that WRITES this lives in
    /// `SwapDetailsScreen`, inline with the Market/Limit segmented control; this
    /// is the read side. No binding is threaded down: `@AppStorage` instances
    /// sharing a key observe the same `UserDefaults`, so the write there redraws
    /// here. It also means the choice survives relaunch — comparing layouts
    /// means backgrounding the app, and re-picking on every cold start would
    /// make that tedious.
    @AppStorage("limitLayoutVariant") private var layoutVariant: LimitLayoutVariant = .accordion

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
        let interactor = DefaultLimitSwapInteractor(quoteService: ThorchainService.shared)
        let model = LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
        model.targetUsdPricePerUnit = Decimal(initialToCoin.price)
        model.sourceUsdPricePerUnit = Decimal(initialFromCoin.price)
        self._vm = State(initialValue: model)
    }

    var body: some View {
        // The container is load-bearing despite its single child: it gives the
        // modifiers below a STABLE identity. Hung directly off `selectedBody`
        // they would belong to a `_ConditionalContent` that changes type when
        // the variant switches, so `.task` would re-run and its
        // `selectPresetPct(0)` would silently reset the reviewer's amount on
        // every flip — destroying the like-for-like comparison the picker is
        // for. Anchored here, the VM and the entered order survive the switch.
        VStack(spacing: 0) {
            selectedBody
        }
        .task {
            async let supportedChains: () = vm.refreshSupportedChains()
            async let marketPrice: () = vm.refreshMarketPrice()
            async let queueGate: () = vm.refreshAdvancedSwapQueueGate()
            _ = await (supportedChains, marketPrice, queueGate)
            vm.selectPresetPct(0, userInitiated: false)
        }
        .onChange(of: limitFromCoin) { _, newCoin in
            vm.selectFromAsset(LimitSwapAsset(coin: newCoin))
            vm.sourceUsdPricePerUnit = Decimal(newCoin.price)
            // Debounced + coalesced: a swap mutates both coins, so both onChanges
            // fire — the scheduler cancels the first so only one refresh runs.
            vm.schedulePairRefresh(sourceCoin: newCoin, targetCoin: limitToCoin)
        }
        .onChange(of: limitToCoin) { _, newCoin in
            vm.selectToAsset(LimitSwapAsset(coin: newCoin))
            vm.targetUsdPricePerUnit = Decimal(newCoin.price)
            vm.schedulePairRefresh(sourceCoin: limitFromCoin, targetCoin: newCoin)
        }
        .onChange(of: vm.draft.sourceAmount) { _, _ in
            // The network fee (UTXO especially) depends on the amount; refresh the
            // estimate (debounced) so the Verify / Done screens show the placed
            // order's fee — without resetting the user's target price.
            vm.scheduleFeeEstimate(sourceCoin: limitFromCoin, targetCoin: limitToCoin)
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
        .alert(
            "limitSwap.error.title".localized,
            isPresented: Binding(
                get: { vm.placeOrderError != nil },
                set: { if !$0 { vm.placeOrderError = nil } }
            ),
            presenting: vm.placeOrderError
        ) { _ in
            Button("ok".localized, role: .cancel) { vm.placeOrderError = nil }
        } message: { error in
            Text(error.message)
        }
    }

    // MARK: - Layout variants (design-review branch only)

    /// Renders the selected candidate layout. Every case is handed the same VM,
    /// the same coin state and the same callbacks — `.threeSection` takes no
    /// `toCoin` because that layout reads the target's rate off the VM instead
    /// (see `LimitSwapBodyThreeSectionView.fromCoin`); the other three need it.
    @ViewBuilder
    private var selectedBody: some View {
        switch layoutVariant {
        case .accordion:
            LimitSwapBodyView(
                vm: vm,
                fromCoin: limitFromCoin,
                toCoin: limitToCoin,
                onPickFromAsset: { showFromCoinPicker = true },
                onPickToAsset: { showToCoinPicker = true },
                onSwapAssets: handleSwapAssets,
                onPlaceOrder: handlePlaceOrder
            )
        case .assetsFirst:
            LimitSwapBodyAssetsFirstView(
                vm: vm,
                fromCoin: limitFromCoin,
                toCoin: limitToCoin,
                onPickFromAsset: { showFromCoinPicker = true },
                onPickToAsset: { showToCoinPicker = true },
                onSwapAssets: handleSwapAssets,
                onPlaceOrder: handlePlaceOrder
            )
        case .uniswapFlat:
            LimitSwapBodyUniswapView(
                vm: vm,
                fromCoin: limitFromCoin,
                toCoin: limitToCoin,
                onPickFromAsset: { showFromCoinPicker = true },
                onPickToAsset: { showToCoinPicker = true },
                onSwapAssets: handleSwapAssets,
                onPlaceOrder: handlePlaceOrder
            )
        case .threeSection:
            LimitSwapBodyThreeSectionView(
                vm: vm,
                fromCoin: limitFromCoin,
                onPickFromAsset: { showFromCoinPicker = true },
                onPickToAsset: { showToCoinPicker = true },
                onSwapAssets: handleSwapAssets,
                onPlaceOrder: handlePlaceOrder
            )
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
        // All validation / memo-assembly / byte-cap / record construction lives
        // in the VM (`preparePlaceableOrder`) so it is unit-testable and runs
        // the shared `validateLimitSwapInputs` gate in production. The view only
        // turns a prepared order into a `SwapTransaction` and navigates.
        //
        // Built SYNCHRONOUSLY (no await) so the Verify transaction is a consistent
        // snapshot of the prepared draft and a single tap enqueues a single route
        // — matching every other place/continue flow. `networkFeeEstimate` carries
        // the best-effort source-chain fee ESTIMATE (`vm.networkFeeEstimate`),
        // refreshed on asset/amount change; it drives display + tx-history only. The
        // REAL fee is re-derived from a fresh fetch at keysign time in
        // LimitSwapPayloadAssembler, so a slightly-stale estimate never affects the
        // signed transaction.
        guard let prepared = vm.preparePlaceableOrder() else { return }
        let record = prepared.record

        let transaction = SwapTransaction(
            fromCoin: limitFromCoin,
            toCoin: limitToCoin,
            fromAmount: limitFromCoin.decimal(for: vm.draft.sourceAmount),
            kind: .limit(record),
            gas: 0,
            // `gas`/`gasLimit` are the market-swap EVM fee-display fields (from a
            // market quote) and stay 0 for limit — the Verify/Done fee display uses
            // the `thorchainFee` estimate below, and signing re-derives the EVM gas
            // limit in LimitSwapPayloadAssembler for native-EVM sources.
            gasLimit: 0,
            // `thorchainFee` is the market protocol-fee field (feeds SwapCryptoLogic.fee)
            // and stays 0 for a limit order — the limit network fee lives in its own
            // `networkFeeEstimate` field below.
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            // Pre-estimated source-chain broadcast fee (fee coin's smallest units)
            // so the shared Verify/Done screens can show and persist the limit
            // order's network fee — the resting `=<` order carries no market quote.
            networkFeeEstimate: vm.networkFeeEstimate,
            // Gas is paid in the source chain's NATIVE coin, not the source
            // token: an ERC20 source (e.g. ETH.USDC) pays ETH. Resolve the native
            // sibling (same helper the market swap uses) so the fee display AND
            // the sign-time `balanceError` gate read wei against ETH's 18 decimals
            // — not the token's, which showed the fee as billions and tripped a
            // false `insufficientGas`. Falls back to the source coin (native
            // sources return themselves).
            feeCoin: SwapCryptoLogic.feeCoin(fromCoin: limitFromCoin, fromCoins: vault.coins),
            advancedSettings: .default
        )

        router.navigate(to: SwapRoute.verify(
            transaction: transaction,
            retrySignal: SwapRetrySignal(),
            vaultPubKeyECDSA: vault.pubKeyECDSA
        ))
    }

    private func handleSwapAssets() {
        let oldFrom = limitFromCoin
        limitFromCoin = limitToCoin
        limitToCoin = oldFrom
        // onChange handlers will sync the new coins into the VM via
        // selectFromAsset/selectToAsset.
    }
}
