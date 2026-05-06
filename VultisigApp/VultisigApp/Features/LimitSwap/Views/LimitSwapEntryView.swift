//
//  LimitSwapEntryView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Wrapper that owns the `LimitSwapFormViewModel` lifecycle and renders the
/// body. Lives at this layer so `SwapCryptoView` doesn't need to manage VM
/// construction itself. The VM is built once on first appearance from the
/// supplied initial coins; subsequent renders reuse it.
struct LimitSwapEntryView: View {

    let initialFromCoin: Coin
    let initialToCoin: Coin
    let vault: Vault

    @State private var vm: LimitSwapFormViewModel?
    @State private var confirmationVM: LimitSwapConfirmationViewModel?
    @State private var isConfirmationSheetPresented: Bool = false

    var body: some View {
        Group {
            if let vm {
                LimitSwapBodyView(
                    vm: vm,
                    onPickAssetPair: handlePickAssetPair,
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
            fromAsset: LimitSwapAsset(coin: initialFromCoin),
            toAsset: LimitSwapAsset(coin: initialToCoin)
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

    private func handlePickAssetPair() {
        // TODO(§7 follow-up): wire to the existing market-swap asset picker
        // sheet. Tracked in design-flags.md item #2.
    }

    private func handlePlaceOrder() {
        guard let vm,
              let fromMemo = vm.draft.fromAsset.memoSymbol,
              let toMemo = vm.draft.toAsset.memoSymbol,
              let destAddress = vm.destinationAddress(),
              vm.draft.sourceAmount > 0,
              vm.draft.targetPrice > 0
        else {
            // The Place button is disabled in the body when these conditions
            // fail, so reaching here implies an in-flight desync — silently
            // return until §8.B introduces a richer error pathway.
            return
        }

        // Phase 1 hardcodes non-referred affiliate (vi/50). The full referral
        // path (myref/vi, 10/35) lands alongside the real sign wiring in §8.B
        // when the affiliate config is read from vault tier metadata.
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
            // on success persist via LimitOrderStorageService with the
            // inbound TX hash, then advance to the success screen. For §8.A
            // the wiring stops here — the byte-cap pre-flight in the VM still
            // runs (and surfaces in the sheet's error banner if it fails).
        }
    }
}
