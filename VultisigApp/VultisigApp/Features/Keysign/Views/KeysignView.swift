//
//  Keysign.swift
//  VultisigApp

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "keysign-view")

struct KeysignView: View {
    let vault: Vault
    let keysignCommittee: [String]
    let mediatorURL: String
    let sessionID: String
    let keysignType: KeyType
    let messsageToSign: [String]
    let keysignPayload: KeysignPayload? // need to pass it along to the next view
    let customMessagePayload: CustomMessagePayload?
    let transferViewModel: TransferViewModel?
    let encryptionKeyHex: String
    let isInitiateDevice: Bool
    var decodedFunctionName: String? = nil
    var decodedTokenAmount: String? = nil
    var decodedTokenTicker: String? = nil
    var decodedTokenLogo: String? = nil
    var decodedTokenDisplay: String? = nil
    var decodedTokenIsUnlimited: Bool = false
    var decodedFunctionSignature: String? = nil
    var decodedFunctionArguments: String? = nil
    @StateObject var viewModel = KeysignViewModel()

    @State var showDoneText = false
    @State var showError = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @EnvironmentObject var globalStateViewModel: GlobalStateViewModel
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        content
            .sensoryFeedback(.success, trigger: showDoneText)
            .sensoryFeedback(.error, trigger: showError)
            .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.status)
            // Observability hook for vultisig-ios#4327: the issue reporter sees
            // the "Signing" screen unblock after backgrounding + foregrounding,
            // which fingerprints iOS auto-resuming a suspended network session.
            // The log line lets us correlate scene transitions with the status
            // trail in `os_log` captures from a TestFlight repro.
            .onChange(of: scenePhase) { oldPhase, newPhase in
                let isSigning: [KeysignStatus] = [.CreatingInstance, .KeysignECDSA, .KeysignEdDSA, .KeysignMLDSA]
                guard isSigning.contains(viewModel.status) else { return }
                logger.info("scenePhase: \(String(describing: oldPhase), privacy: .public) → \(String(describing: newPhase), privacy: .public) while status=\(String(describing: viewModel.status), privacy: .public)")
            }
        #if os(iOS)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                viewModel.stopMessagePuller()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .navigationBarBackButtonHidden(viewModel.status == .KeysignFinished ? true : false)
        #else
            .onDisappear {
                viewModel.stopMessagePuller()
            }
        #endif

    }

    var content: some View {
        ZStack {
            switch viewModel.status {
            case .connectingToFastServer,
                    .CreatingInstance,
                    .KeysignECDSA,
                    .KeysignEdDSA,
                    .KeysignMLDSA:
                // One animation host across connecting -> signing: keeping these
                // in a single switch branch preserves the view's structural
                // identity, so the Rive animation isn't torn down and recreated
                // mid-transition. `connected` flips false -> true through the
                // binding (searching -> signing visual) instead of restarting.
                SendCryptoKeysignView(
                    connected: viewModel.status != .connectingToFastServer,
                    coinLogo: keysignPayload?.coin.logo,
                    progress: viewModel.signingProgress
                )
            case .KeysignFinished:
                keysignFinished
            case .KeysignFailed:
                sendCryptoKeysignView
                    .padding(.horizontal, 16)
            case .KeysignBroadcastUnconfirmed:
                broadcastUnconfirmedView
                    .padding(.horizontal, 16)
            case .KeysignRetryRequested:
                retryRequestedView
            case .KeysignVaultMismatch:
                keysignVaultMismatchErrorView
                    .padding(.horizontal, 16)
            }
        }
        .onLoad {
            Task {
                await setData()
                await viewModel.startKeysign()
            }
        }
        .onChange(of: viewModel.txid) {
            movetoDoneView()
        }
    }

    var keysignFinished: some View {
        ZStack {
            if transferViewModel != nil, keysignPayload != nil {
                forStartKeysign
            } else {
                forJoinKeysign
            }
        }
        .onAppear {
            showDoneText = true
        }
    }

    var forStartKeysign: some View {
        Loader()
    }

    var forJoinKeysign: some View {
        JoinKeysignDoneView(vault: vault, viewModel: viewModel)
            .onAppear {
                globalStateViewModel.showKeysignDoneView = true
            }
            .onDisappear {
                globalStateViewModel.showKeysignDoneView = false
            }
    }

    var sendCryptoKeysignView: some View {
        SendCryptoKeysignView(title: viewModel.keysignError, showError: true)
            .onAppear {
                showError = true
            }
    }

    var retryRequestedView: some View {
        SendCryptoKeysignView(
            title: viewModel.retryReason?.userFacingMessage ?? .empty,
            showError: true,
            errorButtonTitle: "tryAgain".localized,
            errorAction: {
                guard let reason = viewModel.retryReason else { return }
                transferViewModel?.retryBroadcast(reason: reason)
            }
        )
        .onAppear {
            showError = true
        }
    }

    /// Neutral terminal surface for a cancelled broadcast that could not be
    /// positively confirmed on-chain. Shows the deterministic hash + explorer
    /// link so the user can check for themselves, and deliberately does NOT
    /// offer a one-tap re-broadcast (the tx may have landed — double-spend
    /// risk). Never surfaces the internal "CancellationError" string.
    var broadcastUnconfirmedView: some View {
        ErrorView(
            type: .warning,
            title: "broadcastCouldNotConfirmTitle".localized,
            description: "broadcastCouldNotConfirm".localized,
            buttonTitle: "viewOnExplorer".localized
        ) {
            let urlString = viewModel.getTransactionExplorerURL(txid: viewModel.txid)
            if !urlString.isEmpty, let url = URL(string: urlString) {
                openURL(url)
            }
        }
        .onAppear {
            showError = true
        }
    }

    var keysignVaultMismatchErrorView: some View {
        let presentation = ErrorPresentation(.vaultNotLoaded)
        return ErrorView(
            type: presentation.type,
            title: presentation.title,
            description: presentation.description,
            buttonTitle: "tryAgain".localized,
            rawError: presentation.rawError
        ) {
            appViewModel.set(selectedVault: appViewModel.selectedVault, showingVaultSelector: true)
        }
        .onAppear {
            showError = true
        }
    }

    func setData() async {
        if let keysignPayload, keysignPayload.vaultPubKeyECDSA != vault.pubKeyECDSA {
            viewModel.status = .KeysignVaultMismatch
            return
        }

        await viewModel.setData(
            keysignCommittee: self.keysignCommittee,
            mediatorURL: self.mediatorURL,
            sessionID: self.sessionID,
            keysignType: self.keysignType,
            messagesToSign: self.messsageToSign,
            vault: self.vault,
            keysignPayload: keysignPayload,
            customMessagePayload: customMessagePayload,
            encryptionKeyHex: encryptionKeyHex,
            isInitiateDevice: self.isInitiateDevice
        )
        viewModel.decodedFunctionName = decodedFunctionName
        viewModel.decodedTokenAmount = decodedTokenAmount
        viewModel.decodedTokenTicker = decodedTokenTicker
        viewModel.decodedTokenLogo = decodedTokenLogo
        viewModel.decodedTokenDisplay = decodedTokenDisplay
        viewModel.decodedTokenIsUnlimited = decodedTokenIsUnlimited
        viewModel.decodedFunctionSignature = decodedFunctionSignature
        viewModel.decodedFunctionArguments = decodedFunctionArguments
    }

    private func movetoDoneView() {
        // Don't navigate to the success done-screen when the broadcast result is
        // unconfirmed — the txid is set for display only, not as proof of a
        // landed tx. The neutral in-place view handles that state.
        guard viewModel.status != .KeysignBroadcastUnconfirmed else {
            return
        }
        guard let transferViewModel = transferViewModel, !viewModel.txid.isEmpty else {
            return
        }

        transferViewModel.hash = viewModel.txid
        transferViewModel.approveHash = viewModel.approveTxid
        transferViewModel.moveToNextView()
    }
}

#Preview {
    ZStack {
        Background()

        KeysignView(
            vault: Vault.example,
            keysignCommittee: [],
            mediatorURL: "",
            sessionID: "session",
            keysignType: .ECDSA,
            messsageToSign: ["message"],
            keysignPayload: nil,
            customMessagePayload: nil,
            transferViewModel: nil,
            encryptionKeyHex: "",
            isInitiateDevice: false
        )
    }
    .environmentObject(HomeViewModel())
    .environmentObject(GlobalStateViewModel())
    .environmentObject(AppViewModel())
}

#if os(iOS)
import SwiftUI

extension KeysignView {
    var container: some View {
        content
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                viewModel.stopMessagePuller()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .navigationBarBackButtonHidden(viewModel.status == .KeysignFinished ? true : false)
    }
}
#endif
