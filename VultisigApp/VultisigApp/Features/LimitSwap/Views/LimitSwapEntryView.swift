//
//  LimitSwapEntryView.swift
//  VultisigApp
//

import BigInt
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-swap-entry")

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
        guard let fromMemo = vm.draft.fromAsset.memoSymbol,
              let toMemo = vm.draft.toAsset.memoSymbol,
              let destAddress = vm.destinationAddress(),
              vm.draft.sourceAmount > 0,
              vm.draft.targetPrice > 0
        else {
            return
        }

        // Phase 1 routes only native source assets. A non-native (ERC20-style)
        // source would set `toAddress = router` with `approvePayload: nil` and
        // no approve-first keysign, which the THORChain router rejects. The
        // picker filters by chain, not token type, so ETH.USDC is still
        // pickable — guard loudly here so the user gets feedback instead of a
        // failed on-chain tx. (ERC20 approve-first flow is Phase 2.)
        guard limitFromCoin.isNativeToken else {
            logger.error("Place order rejected: non-native source \(limitFromCoin.ticker, privacy: .public) not supported in Phase 1")
            vm.placeOrderError = .nonNativeSourceUnsupported
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

        let chainKind = vm.draft.fromAsset.chain.chainType

        // Memo assembly + byte-cap pre-flight. Both can fail for genuinely
        // user-actionable reasons (a target price that overflows the LIM
        // fixed-point, or a memo that overflows the source chain's per-tx
        // byte budget — realistic on UTXO source + token destination). These
        // must surface to the user via an alert, NOT be swallowed silently:
        // tapping "Place Order" and having nothing happen is a confusing UX,
        // and an overflowed LIM is a fund-safety hazard.
        let memo: String
        do {
            memo = try buildLimitSwapMemo(inputs)
            try assertMemoByteLength(memo, sourceChainKind: chainKind)
        } catch let error as LimitSwapMemoError {
            switch error {
            case let .memoExceedsByteLimit(actual, limit):
                logger.error("Place order rejected: memo \(actual) bytes exceeds \(limit)-byte cap")
                vm.placeOrderError = .memoTooLong(actual: actual, limit: limit)
            case .targetPriceOverflow:
                logger.error("Place order rejected: target price overflowed LIM fixed-point")
                vm.placeOrderError = .targetPriceOverflow
            }
            return
        } catch {
            logger.error("Place order rejected: \(error.localizedDescription, privacy: .public)")
            vm.placeOrderError = .targetPriceOverflow
            return
        }

        let draft = vm.draft
        let record = LimitOrderRecord(
            inboundTxHash: "",  // Filled in by the Done screen after broadcast.
            sourceAsset: fromMemo,
            sourceAmount: draft.sourceAmount.description,
            sourceDecimals: draft.fromAsset.decimals,
            targetAsset: toMemo,
            destAddress: destAddress,
            targetPrice: draft.targetPrice,
            expiryBlocks: computeExpiryBlocks(hours: draft.expiryHours),
            createdAt: Date(),
            status: .pending,
            memo: memo,
            expiryHours: draft.expiryHours
        )

        let transaction = SwapTransaction(
            fromCoin: limitFromCoin,
            toCoin: limitToCoin,
            fromAmount: limitFromCoin.decimal(for: draft.sourceAmount),
            quote: nil,
            gas: 0,
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
