//
//  WalletConnectTransactionRequestSheet.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct WalletConnectTransactionRequestSheet: View {
    let incomingRequest: WalletConnectIncomingRequest
    let coordinator: WalletConnectCoordinator

    @Query(sort: \Vault.order) private var vaults: [Vault]
    @StateObject private var keysignVM = KeysignViewModel()
    @StateObject private var verifyViewModel = FunctionTransactionVerifyViewModel()
    @State private var fastVaultPassword = ""
    @State private var fastPasswordPresented = false
    @State private var keysignView: KeysignView?
    @State private var keysignPayload: KeysignPayload?
    @State private var showPairScreen = false
    @State private var actionError: Error?
    @State private var isRejecting = false
    @State private var isApproving = false
    @State private var didRespond = false

    private var transactionRequestResult: Result<WalletConnectTransactionRequest, Error> {
        Result {
            try WalletConnectTransactionRequestBuilder().build(
                incoming: incomingRequest,
                binding: WalletConnectSessionBindingStore.shared.binding(for: incomingRequest.topic),
                vaults: vaults
            )
        }
    }

    private var transactionRequest: WalletConnectTransactionRequest? {
        try? transactionRequestResult.get()
    }

    private var signingVault: Vault? {
        guard let transactionRequest else { return nil }
        return vaults.first { $0.pubKeyECDSA == transactionRequest.vaultPubKeyECDSA }
    }

    var body: some View {
        ZStack {
            switch transactionRequestResult {
            case .success(let request):
                content(for: request)
            case .failure(let error):
                rejectionContent(error: error)
            }
        }
        .background(Theme.colors.bgPrimary)
        .interactiveDismissDisabled()
        .withError(error: $actionError, errorType: .warning) {
            actionError = nil
        }
    }

    @ViewBuilder
    private func content(for request: WalletConnectTransactionRequest) -> some View {
        if keysignVM.status == .KeysignFinished || keysignView != nil || showPairScreen || !fastVaultPassword.isEmpty {
            signingContent(for: request)
        } else {
            approvalContent(for: request)
        }
    }

    private func approvalContent(for request: WalletConnectTransactionRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(for: request)
                WalletConnectVerifyContextView(verifyContext: request.verifyContext)
                detailRow(title: "walletConnectTransactionMethod".localized, value: request.method)
                detailRow(title: "walletConnectTransactionChain".localized, value: request.chain.name)
                detailRow(title: "walletConnectTransactionFrom".localized, value: request.from)
                detailRow(title: "walletConnectTransactionTo".localized, value: request.to)
                detailRow(
                    title: "walletConnectTransactionValue".localized,
                    value: "\(request.valueAmount) \(request.transaction.coin.ticker)"
                )
                detailRow(
                    title: "walletConnectTransactionData".localized,
                    value: request.data.isEmpty ? "walletConnectTransactionEmptyData".localized : request.data
                )
                overrideRows(for: request)
                actions(for: request)
            }
            .padding(24)
        }
    }

    private func signingContent(for request: WalletConnectTransactionRequest) -> some View {
        ZStack {
            if keysignVM.status == .KeysignFinished {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("walletConnectTransactionResponding".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                .task { await respondIfNeeded(request) }
            } else if let vault = signingVault, let fastPassword = fastVaultPassword.nilIfEmpty, let keysignPayload {
                KeysignView(
                    viewModel: keysignVM,
                    source: .fast(
                        vault: vault,
                        keysignPayload: keysignPayload,
                        customMessagePayload: nil,
                        fastVaultPassword: fastPassword
                    )
                )
            } else if showPairScreen, let vault = signingVault, let keysignPayload {
                PairScreen(
                    vault: vault,
                    keysignPayload: keysignPayload,
                    customMessagePayload: nil,
                    fastVaultPassword: nil,
                    title: "walletConnectTransactionRequest".localized
                ) { input in
                    self.keysignView = KeysignView(
                        viewModel: keysignVM,
                        vault: input.vault,
                        keysignCommittee: input.keysignCommittee,
                        mediatorURL: input.mediatorURL,
                        sessionID: input.sessionID,
                        keysignType: input.keysignType,
                        messsageToSign: input.messsageToSign,
                        keysignPayload: input.keysignPayload,
                        customMessagePayload: input.customMessagePayload,
                        encryptionKeyHex: input.encryptionKeyHex,
                        isInitiateDevice: input.isInitiateDevice
                    )
                    showPairScreen = false
                }
            } else if let keysignView {
                keysignView
            } else {
                rejectionContent(error: WalletConnectTransactionRequestError.missingBoundVault(incomingRequest.topic))
            }
        }
    }

    private func rejectionContent(error: Error) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("walletConnectTransactionRequest".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(error.localizedDescription)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.alertWarning)
#if DEBUG
            detailRow(title: "Debug method", value: incomingRequest.method)
            detailRow(title: "Debug chain", value: incomingRequest.chainId ?? "nil")
            detailRow(title: "Debug params", value: incomingRequest.paramsJSON)
#endif
            PrimaryButton(
                title: "reject".localized,
                isLoading: isRejecting,
                type: .secondary,
                action: reject
            )
            .disabled(isRejecting)
        }
        .padding(24)
        .onAppear {
            logTransactionRequestFailure(error)
        }
    }

    private func logTransactionRequestFailure(_ error: Error) {
        let chainId = incomingRequest.chainId ?? "nil"
        Log.app.other.error(
            "WalletConnect transaction request failed: method=\(incomingRequest.method, privacy: .public) chain=\(chainId, privacy: .public) error=\(error.localizedDescription, privacy: .public) params=\(incomingRequest.paramsJSON, privacy: .public)"
        )
    }

    private func header(for request: WalletConnectTransactionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("walletConnectTransactionRequest".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(request.dappMetadata.name)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(request.dappMetadata.host)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.colors.bgSurface2)
                .clipShape(Theme.radius.md.shape)
        }
    }

    @ViewBuilder
    private func overrideRows(for request: WalletConnectTransactionRequest) -> some View {
        ForEach(request.requestedOverrides.displayFields, id: \.0) { field, value in
            detailRow(title: "WalletConnect override: \(field)", value: value.description)
        }
    }

    private func actions(for request: WalletConnectTransactionRequest) -> some View {
        VStack(spacing: 12) {
            SigningCTAButtons(
                isFastVault: signingVault?.offersFastSigning ?? false,
                isDisabled: signingVault == nil || isApproving || isRejecting || verifyViewModel.isLoading,
                singleSignTitle: "signTransaction",
                onFastSign: { prepareSigning(request, fast: true) },
                onPairedSign: { prepareSigning(request, fast: false) }
            )
            .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                if let vault = signingVault {
                    FastVaultEnterPasswordView(
                        isPresented: $fastPasswordPresented,
                        password: $fastVaultPassword,
                        vault: vault,
                        onSubmit: { isApproving = true }
                    )
                }
            }

            PrimaryButton(
                title: "reject".localized,
                isLoading: isRejecting,
                type: .secondary,
                action: reject
            )
            .disabled(isApproving || isRejecting)
        }
    }

    private func prepareSigning(_ request: WalletConnectTransactionRequest, fast: Bool) {
        guard signingVault != nil else { return }
        isApproving = true
        Task { @MainActor in
            do {
                keysignPayload = try await verifyViewModel
                    .createKeysignPayload(tx: request.transaction)
                    .applyingWalletConnectOverrides(request.requestedOverrides)
                if fast {
                    fastPasswordPresented = true
                } else {
                    keysignView = nil
                    showPairScreen = true
                }
            } catch {
                actionError = error
                isApproving = false
            }
        }
    }

    private func respondIfNeeded(_ request: WalletConnectTransactionRequest) async {
        guard !didRespond else { return }
        guard keysignVM.status == .KeysignFinished, !keysignVM.txid.isEmpty else { return }
        didRespond = true
        do {
            try await coordinator.approveTransactionRequest(request, transactionHash: keysignVM.txid)
        } catch {
            actionError = error
            didRespond = false
        }
    }

    private func reject() {
        isRejecting = true
        Task { @MainActor in
            do {
                try await coordinator.rejectMessageRequest(incomingRequest)
            } catch {
                actionError = error
            }
            isRejecting = false
        }
    }
}

private struct WalletConnectVerifyContextView: View {
    let verifyContext: WalletConnectVerifyContext?

    var body: some View {
        if let verifyContext {
            VStack(alignment: .leading, spacing: 8) {
                Text(verifyContext.titleLocalizationKey.localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(verifyContext.isWarning ? Theme.colors.alertWarning : Theme.colors.textPrimary)
                Text(String(format: verifyContext.messageLocalizationKey.localized, verifyContext.origin))
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .clipShape(Theme.radius.md.shape)
        }
    }
}
