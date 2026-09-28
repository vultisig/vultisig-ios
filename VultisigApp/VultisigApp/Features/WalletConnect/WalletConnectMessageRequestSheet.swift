//
//  WalletConnectMessageRequestSheet.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct WalletConnectMessageRequestSheet: View {
    let incomingRequest: WalletConnectIncomingRequest
    let coordinator: WalletConnectCoordinator

    @Query(sort: \Vault.order) private var vaults: [Vault]
    @StateObject private var keysignVM = KeysignViewModel()
    @State private var fastVaultPassword = ""
    @State private var fastPasswordPresented = false
    @State private var keysignView: KeysignView?
    @State private var showPairScreen = false
    @State private var actionError: Error?
    @State private var isRejecting = false
    @State private var isApproving = false
    @State private var didRespond = false

    private var messageRequestResult: Result<WalletConnectMessageRequest, Error> {
        Result {
            try WalletConnectMessageRequestBuilder().build(
                incoming: incomingRequest,
                binding: WalletConnectSessionBindingStore.shared.binding(for: incomingRequest.topic),
                vaults: vaults
            )
        }
    }

    private var messageRequest: WalletConnectMessageRequest? {
        try? messageRequestResult.get()
    }

    private var signingVault: Vault? {
        guard let messageRequest else { return nil }
        return vaults.first { $0.pubKeyECDSA == messageRequest.vaultPubKeyECDSA }
    }

    var body: some View {
        ZStack {
            switch messageRequestResult {
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
    private func content(for request: WalletConnectMessageRequest) -> some View {
        if keysignVM.status == .KeysignFinished || keysignView != nil || showPairScreen || !fastVaultPassword.isEmpty {
            signingContent(for: request)
        } else {
            approvalContent(for: request)
        }
    }

    private func approvalContent(for request: WalletConnectMessageRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(for: request)
                verifyContextView(request.verifyContext)
                detailRow(title: "walletConnectMessageMethod".localized, value: request.method)
                detailRow(title: "walletConnectMessageChain".localized, value: request.chain.name)
                detailRow(title: "walletConnectMessageAddress".localized, value: request.address)
                detailRow(title: "messageToSign".localized, value: request.displayMessage)
                actions(for: request)
            }
            .padding(24)
        }
    }

    private func signingContent(for request: WalletConnectMessageRequest) -> some View {
        ZStack {
            if keysignVM.status == .KeysignFinished {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("walletConnectMessageResponding".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                .task { await respondIfNeeded(request) }
            } else if let vault = signingVault, let fastPassword = fastVaultPassword.nilIfEmpty {
                KeysignView(
                    viewModel: keysignVM,
                    source: .fast(
                        vault: vault,
                        keysignPayload: nil,
                        customMessagePayload: request.customMessagePayload,
                        fastVaultPassword: fastPassword
                    )
                )
            } else if showPairScreen, let vault = signingVault {
                PairScreen(
                    vault: vault,
                    customMessagePayload: request.customMessagePayload,
                    fastVaultPassword: nil,
                    title: "walletConnectMessageRequest".localized
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
                rejectionContent(error: WalletConnectMessageRequestError.missingBoundVault(incomingRequest.topic))
            }
        }
    }

    private func rejectionContent(error: Error) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("walletConnectMessageRequest".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(error.localizedDescription)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.alertWarning)
            PrimaryButton(
                title: "reject".localized,
                isLoading: isRejecting,
                type: .secondary,
                action: reject
            )
            .disabled(isRejecting)
        }
        .padding(24)
    }

    private func header(for request: WalletConnectMessageRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("walletConnectMessageRequest".localized)
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

    @ViewBuilder
    private func verifyContextView(_ verifyContext: WalletConnectVerifyContext?) -> some View {
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

    private func actions(for request: WalletConnectMessageRequest) -> some View {
        VStack(spacing: 12) {
            SigningCTAButtons(
                isFastVault: signingVault?.offersFastSigning ?? false,
                isDisabled: signingVault == nil || isApproving || isRejecting,
                singleSignTitle: "approve",
                onFastSign: { fastPasswordPresented = true },
                onPairedSign: { startPairedSigning(request) }
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

    private func startPairedSigning(_: WalletConnectMessageRequest) {
        guard signingVault != nil else { return }
        isApproving = true
        keysignView = nil
        showPairScreen = true
    }

    private func respondIfNeeded(_ request: WalletConnectMessageRequest) async {
        guard !didRespond else { return }
        didRespond = true
        do {
            try await coordinator.approveMessageRequest(request, signature: keysignVM.customMessageSignature())
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
