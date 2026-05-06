//
//  LimitSwapEntryView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Wrapper that owns the `LimitSwapFormViewModel` lifecycle plus Limit's
/// **independent** coin selection state. The initial from/to coins seed
/// from `SwapTransaction` for convenience but subsequent changes via the
/// asset picker stay local — they do not mutate the Market path's
/// SwapTransaction.
struct LimitSwapEntryView: View {

    let initialFromCoin: Coin
    let initialToCoin: Coin
    let vault: Vault

    @State private var vm: LimitSwapFormViewModel?

    // Independent coin state. The picker mutates these directly; an onChange
    // syncs the result into the VM's draft via LimitSwapAsset(coin:).
    @State private var limitFromCoin: Coin
    @State private var limitToCoin: Coin

    @State private var showFromCoinPicker: Bool = false
    @State private var showToCoinPicker: Bool = false

    @State private var confirmationVM: LimitSwapConfirmationViewModel?
    @State private var isConfirmationSheetPresented: Bool = false

    init(initialFromCoin: Coin, initialToCoin: Coin, vault: Vault) {
        self.initialFromCoin = initialFromCoin
        self.initialToCoin = initialToCoin
        self.vault = vault
        self._limitFromCoin = State(initialValue: initialFromCoin)
        self._limitToCoin = State(initialValue: initialToCoin)
    }

    var body: some View {
        Group {
            if let vm {
                LimitSwapBodyView(
                    vm: vm,
                    onPickFromAsset: { showFromCoinPicker = true },
                    onPickToAsset: { showToCoinPicker = true },
                    onPlaceOrder: handlePlaceOrder
                )
            } else {
                Color.clear
            }
        }
        .onAppear {
            if vm == nil {
                vm = makeViewModel()
            }
        }
        .onChange(of: limitFromCoin) { _, newCoin in
            vm?.selectFromAsset(LimitSwapAsset(coin: newCoin))
        }
        .onChange(of: limitToCoin) { _, newCoin in
            vm?.selectToAsset(LimitSwapAsset(coin: newCoin))
        }
        .crossPlatformSheet(isPresented: $showFromCoinPicker) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $showFromCoinPicker,
                selectedCoin: $limitFromCoin,
                selectedChain: limitFromCoin.chain
            )
        }
        .crossPlatformSheet(isPresented: $showToCoinPicker) {
            SwapCoinPickerView(
                vault: vault,
                showSheet: $showToCoinPicker,
                selectedCoin: $limitToCoin,
                selectedChain: limitToCoin.chain
            )
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

    // MARK: - VM construction

    private func makeViewModel() -> LimitSwapFormViewModel {
        let draft = LimitSwapDraft(
            fromAsset: LimitSwapAsset(coin: limitFromCoin),
            toAsset: LimitSwapAsset(coin: limitToCoin)
        )
        let interactor = DefaultLimitSwapInteractor(
            quoteService: ThorchainService.shared,
            storage: LimitOrderStorageService()
        )
        return LimitSwapFormViewModel(
            initialDraft: draft,
            vault: vault,
            interactor: interactor
        )
    }

    // MARK: - Place flow

    private func handlePlaceOrder() {
        guard let vm,
              let fromMemo = vm.draft.fromAsset.memoSymbol,
              let toMemo = vm.draft.toAsset.memoSymbol,
              let destAddress = vm.destinationAddress(),
              vm.draft.sourceAmount > 0,
              vm.draft.targetPrice > 0
        else {
            return
        }

        // Phase 1 hardcodes non-referred affiliate (vi/50). Real referral
        // wiring lands in §8.B.
        let inputs = LimitSwapInputs(
            sourceAsset: fromMemo,
            sourceAmount: vm.draft.sourceAmount,
            sourceDecimals: vm.draft.fromAsset.decimals,
            targetAsset: toMemo,
            destAddress: destAddress,
            targetPrice: vm.draft.targetPrice,
            expiryHours: vm.draft.expiryHours,
            affiliate: "vi",
            affiliateBps: "50"
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

    private func handleSignAttempt() async {
        guard let confirmationVM else { return }

        await confirmationVM.attemptSign {
            // TODO(§8.B): assemble KeysignPayload, run TSS sign + broadcast,
            // on success persist via LimitOrderStorageService.
        }
    }
}
