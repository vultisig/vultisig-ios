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
            async let supportedChains: () = vm.refreshSupportedChains()
            async let marketPrice: () = vm.refreshMarketPrice()
            async let queueGate: () = vm.refreshAdvancedSwapQueueGate()
            _ = await (supportedChains, marketPrice, queueGate)
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
        guard let prepared = vm.preparePlaceableOrder() else { return }
        let record = prepared.record

        let transaction = SwapTransaction(
            fromCoin: limitFromCoin,
            toCoin: limitToCoin,
            fromAmount: limitFromCoin.decimal(for: vm.draft.sourceAmount),
            quote: nil,
            gas: 0,
            // No EVM gas oracle on the limit path (THORChain deposit, no market
            // quote) — matches `gas: 0`. `gasLimit` was added on `main` for the
            // EVM fee-reconciliation display, which limit orders don't surface.
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: limitFromCoin,
            limitContext: record,
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
