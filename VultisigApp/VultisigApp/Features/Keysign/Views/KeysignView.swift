//
//  Keysign.swift
//  VultisigApp

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "keysign-view")

struct KeysignView: View {
    /// The keysign ceremony view-model, owned by the host (initiator, cosigner,
    /// or custom-message screen) and observed here. Lifting it to the host is
    /// what lets every host own the crossfade from this animation to its own
    /// Done surface — this view is purely the signing animation now.
    @ObservedObject var viewModel: KeysignViewModel
    let source: KeysignStartInput
    /// Host-supplied action for the broadcast-failure retry (pops to verify).
    /// A UI action closure — only the initiator wires it; the cosigner and
    /// custom-message paths leave it nil (they have no in-place retry surface).
    let onRetry: ((BroadcastRetryReason) -> Void)?
    var decodedFunctionName: String? = nil
    var decodedTokenAmount: String? = nil
    var decodedTokenTicker: String? = nil
    var decodedTokenLogo: String? = nil
    var decodedTokenDisplay: String? = nil
    var decodedTokenIsUnlimited: Bool = false
    var decodedFunctionSignature: String? = nil
    var decodedFunctionArguments: String? = nil

    @State var showError = false
    /// The in-flight keysign run (fast bootstrap + ceremony). Tracked so it can
    /// be cancelled on teardown / superseded on retry — an untracked task would
    /// let a fast-vault bootstrap keep waking Vultiserver and sign off-screen
    /// after the user backs out.
    @State private var startTask: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @EnvironmentObject var appViewModel: AppViewModel

    /// The keysign payload supplied up front — used only for the connecting/
    /// signing coin logo and the finished-branch selection. The view-model
    /// holds the authoritative (possibly bootstrap-refreshed) payload once the
    /// ceremony starts.
    private var sourceKeysignPayload: KeysignPayload? {
        switch source {
        case .ready(let input): return input.keysignPayload
        case .fast(_, let keysignPayload, _, _): return keysignPayload
        }
    }

    private var decodedMetadata: KeysignDecodedMetadata {
        KeysignDecodedMetadata(
            functionName: decodedFunctionName,
            tokenAmount: decodedTokenAmount,
            tokenTicker: decodedTokenTicker,
            tokenLogo: decodedTokenLogo,
            tokenDisplay: decodedTokenDisplay,
            tokenIsUnlimited: decodedTokenIsUnlimited,
            functionSignature: decodedFunctionSignature,
            functionArguments: decodedFunctionArguments
        )
    }

    init(
        viewModel: KeysignViewModel,
        source: KeysignStartInput,
        onRetry: ((BroadcastRetryReason) -> Void)? = nil,
        decodedFunctionName: String? = nil,
        decodedTokenAmount: String? = nil,
        decodedTokenTicker: String? = nil,
        decodedTokenLogo: String? = nil,
        decodedTokenDisplay: String? = nil,
        decodedTokenIsUnlimited: Bool = false,
        decodedFunctionSignature: String? = nil,
        decodedFunctionArguments: String? = nil
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.source = source
        self.onRetry = onRetry
        self.decodedFunctionName = decodedFunctionName
        self.decodedTokenAmount = decodedTokenAmount
        self.decodedTokenTicker = decodedTokenTicker
        self.decodedTokenLogo = decodedTokenLogo
        self.decodedTokenDisplay = decodedTokenDisplay
        self.decodedTokenIsUnlimited = decodedTokenIsUnlimited
        self.decodedFunctionSignature = decodedFunctionSignature
        self.decodedFunctionArguments = decodedFunctionArguments
    }

    /// Legacy convenience for callers that already hold a complete committee (a
    /// joining cosigner, the paired custom-message path): packs the fields into
    /// a `.ready` source.
    init(
        viewModel: KeysignViewModel,
        vault: Vault,
        keysignCommittee: [String],
        mediatorURL: String,
        sessionID: String,
        keysignType: KeyType,
        messsageToSign: [String],
        keysignPayload: KeysignPayload?,
        customMessagePayload: CustomMessagePayload?,
        encryptionKeyHex: String,
        isInitiateDevice: Bool,
        onRetry: ((BroadcastRetryReason) -> Void)? = nil,
        decodedFunctionName: String? = nil,
        decodedTokenAmount: String? = nil,
        decodedTokenTicker: String? = nil,
        decodedTokenLogo: String? = nil,
        decodedTokenDisplay: String? = nil,
        decodedTokenIsUnlimited: Bool = false,
        decodedFunctionSignature: String? = nil,
        decodedFunctionArguments: String? = nil
    ) {
        self.init(
            viewModel: viewModel,
            source: .ready(KeysignInput(
                vault: vault,
                keysignCommittee: keysignCommittee,
                mediatorURL: mediatorURL,
                sessionID: sessionID,
                keysignType: keysignType,
                messsageToSign: messsageToSign,
                keysignPayload: keysignPayload,
                customMessagePayload: customMessagePayload,
                encryptionKeyHex: encryptionKeyHex,
                isInitiateDevice: isInitiateDevice
            )),
            onRetry: onRetry,
            decodedFunctionName: decodedFunctionName,
            decodedTokenAmount: decodedTokenAmount,
            decodedTokenTicker: decodedTokenTicker,
            decodedTokenLogo: decodedTokenLogo,
            decodedTokenDisplay: decodedTokenDisplay,
            decodedTokenIsUnlimited: decodedTokenIsUnlimited,
            decodedFunctionSignature: decodedFunctionSignature,
            decodedFunctionArguments: decodedFunctionArguments
        )
    }

    var body: some View {
        content
            .sensoryFeedback(.success, trigger: viewModel.status == .KeysignFinished)
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
                startTask?.cancel()
                viewModel.stopMessagePuller()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .navigationBarBackButtonHidden(viewModel.status == .KeysignFinished ? true : false)
        #else
            .onDisappear {
                startTask?.cancel()
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
                    .KeysignMLDSA,
                    .KeysignFinished:
                // One animation host across connecting -> signing -> finished:
                // keeping these in a single switch branch preserves the view's
                // structural identity, so the Rive animation isn't torn down and
                // recreated mid-transition. `connected` flips false -> true
                // through the binding (searching -> signing visual) instead of
                // restarting. `.KeysignFinished` holds the completed animation
                // (progress 100) in place until the host crossfades to its own
                // Done surface.
                SendCryptoKeysignView(
                    connected: viewModel.status != .connectingToFastServer,
                    coinLogo: sourceKeysignPayload?.coin.logo,
                    progress: viewModel.signingProgress
                )
            case .connectingToFastServerFailed:
                fastBootstrapErrorView
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
            startKeysignFlow()
        }
    }

    /// Starts (or retries) the keysign run, tracking the task so teardown can
    /// cancel it and a retry supersedes the previous attempt.
    private func startKeysignFlow() {
        startTask?.cancel()
        startTask = Task { await viewModel.start(source: source, decoded: decodedMetadata) }
    }

    /// Fast-vault bootstrap failure surface. Reuses the shared keysign error
    /// view with a retry that re-runs the bootstrap in place — distinct from
    /// the broadcast-failure retry, which pops to verify.
    var fastBootstrapErrorView: some View {
        SendCryptoKeysignView(
            title: viewModel.keysignError,
            showError: true,
            coinLogo: sourceKeysignPayload?.coin.logo,
            errorButtonTitle: "tryAgain".localized,
            errorAction: {
                startKeysignFlow()
            }
        )
        .onAppear {
            showError = true
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
                onRetry?(reason)
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

}

#Preview {
    ZStack {
        Background()

        KeysignView(
            viewModel: KeysignViewModel(),
            vault: Vault.example,
            keysignCommittee: [],
            mediatorURL: "",
            sessionID: "session",
            keysignType: .ECDSA,
            messsageToSign: ["message"],
            keysignPayload: nil,
            customMessagePayload: nil,
            encryptionKeyHex: "",
            isInitiateDevice: false
        )
    }
    .environmentObject(AppViewModel())
}
