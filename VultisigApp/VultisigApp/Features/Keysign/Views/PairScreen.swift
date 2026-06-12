//
//  PairScreen.swift
//  VultisigApp
//

import SwiftUI

/// Shared pairing screen for every keysign-side flow (Send, Swap, FunctionCall,
/// QBTC claim, custom message). Owns the screen chrome that used to be
/// duplicated across each per-flow wrapper: the `Screen` container, the title,
/// the fast-vault chromeless block, and the trailing QR-share toolbar. The
/// signing engine itself stays in `KeysignDiscoveryView`; callers supply only
/// the payload, the preview type, and the post-pair navigation closure.
struct PairScreen: View {
    @StateObject private var shareSheetViewModel = ShareSheetViewModel()

    let vault: Vault
    var keysignPayload: KeysignPayload?
    var customMessagePayload: CustomMessagePayload?
    var fastVaultPassword: String?
    var previewType: QRShareSheetType
    var sendPreviewOverride: SendPreviewOverride?
    var swapTransaction: SwapTransaction?
    var presetSession: KeysignSessionInfo?

    /// Overrides the default `"pair"` screen title. Used by the custom-message
    /// flow, which shows the running keysign state title instead.
    var title: String?

    /// Overrides the default share-button visibility (`fastVaultPassword == nil`).
    /// The custom-message flow gates on `!vault.isFastVault` instead.
    var isShareButtonVisible: Bool?

    let onKeysignInput: (KeysignInput) -> Void

    init(
        vault: Vault,
        keysignPayload: KeysignPayload? = nil,
        customMessagePayload: CustomMessagePayload? = nil,
        fastVaultPassword: String? = nil,
        previewType: QRShareSheetType = .Send,
        sendPreviewOverride: SendPreviewOverride? = nil,
        swapTransaction: SwapTransaction? = nil,
        presetSession: KeysignSessionInfo? = nil,
        title: String? = nil,
        isShareButtonVisible: Bool? = nil,
        onKeysignInput: @escaping (KeysignInput) -> Void
    ) {
        self.vault = vault
        self.keysignPayload = keysignPayload
        self.customMessagePayload = customMessagePayload
        self.fastVaultPassword = fastVaultPassword
        self.previewType = previewType
        self.sendPreviewOverride = sendPreviewOverride
        self.swapTransaction = swapTransaction
        self.presetSession = presetSession
        self.title = title
        self.isShareButtonVisible = isShareButtonVisible
        self.onKeysignInput = onKeysignInput
    }

    var body: some View {
        Screen {
            KeysignDiscoveryView(
                vault: vault,
                keysignPayload: keysignPayload,
                customMessagePayload: customMessagePayload,
                fastVaultPassword: fastVaultPassword,
                shareSheetViewModel: shareSheetViewModel,
                previewType: previewType,
                sendPreviewOverride: sendPreviewOverride,
                swapTransaction: swapTransaction,
                contentPadding: 0,
                presetSession: presetSession,
                onKeysignInput: onKeysignInput
            )
        }
        .screenTitle(title ?? "pair".localized)
        .if(fastVaultPassword != nil) {
            $0
                .screenNavigationBarHidden(true)
                .screenEdgeInsets(.zero)
        }
        .screenToolbar {
            CustomToolbarItem(placement: .trailing) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keysign,
                    viewModel: shareSheetViewModel
                )
                .showIf(isShareButtonVisible ?? (fastVaultPassword == nil))
            }
        }
    }
}
