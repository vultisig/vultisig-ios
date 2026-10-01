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
        .background(Color.walletConnectBackground)
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
        VStack(spacing: 0) {
            WalletConnectSheetHeader(
                title: "walletConnectTransactionRequest".localized,
                onClose: isApproving || isRejecting ? nil : reject
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    WalletConnectDAppIdentityPanel(
                        name: request.dappMetadata.name,
                        host: request.dappMetadata.host,
                        iconURL: request.dappMetadata.iconURL,
                        verifyContext: request.verifyContext
                    )

                    WalletConnectVerifyContextView(verifyContext: request.verifyContext)

                    transactionHero(for: request)
                    transferCards(for: request)
                    metadataSection(for: request)
                    nativeTransferAcknowledgments
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            actions(for: request)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .background(Color.walletConnectBackground)
        }
    }

    private func transactionHero(for request: WalletConnectTransactionRequest) -> some View {
        VStack(spacing: 10) {
            AsyncImageView(
                logo: request.transaction.coin.logo,
                size: CGSize(width: 72, height: 72),
                ticker: request.transaction.coin.ticker,
                tokenChainLogo: request.transaction.coin.chain.logo
            )
            Text("\(request.valueAmount) \(request.transaction.coin.ticker)")
                .font(Theme.fonts.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(Color.walletConnectTextPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func transferCards(for request: WalletConnectTransactionRequest) -> some View {
        VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 10) {
                Text("walletConnectFrom".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
                WalletConnectVaultCard(
                    title: signingVault?.name ?? "walletConnectUnknownVault".localized,
                    subtitle: request.from.walletConnectShortAddress,
                    showsChevron: false
                )
                .frame(height: 52)
            }
            .padding(16)
            .background(Color.walletConnectSurface)
            .overlay(Theme.radius.lg.shape.stroke(Color.walletConnectBorder, lineWidth: 1))
            .clipShape(Theme.radius.lg.shape)

            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.walletConnectTextSecondary)
                .frame(width: 33, height: 33)
                .background(Circle().fill(Color.walletConnectSurface))
                .overlay(Circle().stroke(Color.walletConnectBorder, lineWidth: 1))
                .padding(.vertical, -2)

            VStack(alignment: .leading, spacing: 10) {
                Text("walletConnectTo".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: "1A2E47"))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.walletConnectTextSecondary)
                        )
                    Text(request.to.walletConnectShortAddress)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Color.walletConnectTextPrimary)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.walletConnectSurface)
            .overlay(Theme.radius.lg.shape.stroke(Color.walletConnectBorder, lineWidth: 1))
            .clipShape(Theme.radius.lg.shape)
        }
    }

    private func metadataSection(for request: WalletConnectTransactionRequest) -> some View {
        VStack(spacing: 0) {
            WalletConnectMetadataRow(
                label: "walletConnectTransactionChain".localized,
                value: request.chain.name,
                iconName: request.chain.logo
            )
            WalletConnectMetadataRow(
                label: "walletConnectTransactionEstimatedFee".localized,
                value: request.requestedOverrides.feeDisplayValue(ticker: request.transaction.coin.ticker)
            )
            WalletConnectDivider()
                .padding(.vertical, 8)
            disclosureRow(for: request)
        }
    }

    private func disclosureRow(for request: WalletConnectTransactionRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("walletConnectTransactionDetails".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Color.walletConnectTextPrimary)
                    Text(request.method)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Color.walletConnectTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.walletConnectTextSecondary)
            }
            detailRow(title: "walletConnectTransactionData".localized, value: request.data.isEmpty ? "walletConnectTransactionEmptyData".localized : request.data)
            overrideRows(for: request)
        }
    }

    private var nativeTransferAcknowledgments: some View {
        VStack(spacing: 10) {
            acknowledgmentRow("walletConnectAcknowledgeAmount".localized)
            acknowledgmentRow("walletConnectAcknowledgeRecipient".localized)
        }
    }

    private func acknowledgmentRow(_ title: String) -> some View {
        HStack(spacing: 14) {
            Theme.radius.xs.shape
                .stroke(Color.walletConnectTextSecondary, lineWidth: 1.4)
                .frame(width: 22, height: 22)
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Color.walletConnectTextPrimary)
            Spacer()
        }
        .frame(height: 28)
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
                .foregroundStyle(Color.walletConnectTextPrimary)
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
                .foregroundStyle(Color.walletConnectTextPrimary)
            Text(request.dappMetadata.name)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Color.walletConnectTextPrimary)
            Text(request.dappMetadata.host)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Color.walletConnectTextTertiary)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Color.walletConnectTextTertiary)
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Color.walletConnectTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.walletConnectSurface)
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
