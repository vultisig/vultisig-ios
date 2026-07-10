//
//  SwapVerifyScreen.swift
//  VultisigApp
//

import SwiftUI

struct SwapVerifyScreen: View {
    let transaction: SwapTransaction
    let retrySignal: SwapRetrySignal
    let vault: Vault

    @State private var verifyViewModel: SwapVerifyViewModel
    @StateObject private var referredViewModel = ReferredViewModel()

    @State private var fastPasswordPresented = false
    @State private var fastVaultPassword: String = .empty
    @State private var signButtonDisabled = false
    @State private var retryBannerText: String?

    @Environment(\.router) var router

    init(transaction: SwapTransaction, retrySignal: SwapRetrySignal, vault: Vault) {
        self.transaction = transaction
        self.retrySignal = retrySignal
        self.vault = vault
        self._verifyViewModel = State(initialValue: SwapVerifyViewModel(transaction: transaction))
    }

    private var currentTransaction: SwapTransaction { verifyViewModel.transaction }

    var body: some View {
        @Bindable var vm = verifyViewModel
        Screen {
            VStack(spacing: 16) {
                fields
                signButton
                    .disabled(!verifyViewModel.isValidForm(shouldApprove: currentTransaction.isApproveRequired) || verifyViewModel.isLoadingFees || signButtonDisabled)
            }
        }
        .screenTitle("swapOverview".localized)
        .screenToolbar {
            CustomToolbarItem(placement: .trailing, hideSharedBackground: true) {
                refreshCounter
            }
        }
        .withBanner(text: $retryBannerText, style: .error)
        // Surface build-side failures so the user doesn't see "nothing
        // happens" after entering the FastVault password. `buildSwapKeysignPayload`
        // catches errors into `verifyViewModel.error`; without this binding
        // the catch becomes silent.
        .alert(
            "error".localized,
            isPresented: Binding(
                get: { verifyViewModel.error != nil },
                set: { isShown in if !isShown { verifyViewModel.error = nil } }
            ),
            actions: {
                Button("ok".localized, role: .cancel) {}
            },
            message: {
                Text(verifyViewModel.error?.localizedDescription ?? "")
            }
        )
        .swapRefreshTick {
            Task {
                await verifyViewModel.updateTimer(vault: vault, referredCode: referredViewModel.savedReferredCode)
            }
        }
        .onLoad {
            referredViewModel.setData()
            verifyViewModel.onLoad()
            Task {
                await verifyViewModel.scan()
            }
        }
        .onAppear {
            consumePendingRetry()
        }
        .onDisappear {
            verifyViewModel.isLoading = false
            fastVaultPassword = .empty
        }
        .bottomSheet(isPresented: $vm.showSecurityScannerSheet) {
            SecurityScannerBottomSheet(securityScannerModel: verifyViewModel.securityScannerState.result) {
                verifyViewModel.showSecurityScannerSheet = false
                signAndMoveToNextView()
            } onDismissRequest: {
                verifyViewModel.showSecurityScannerSheet = false
            }
        }
    }

    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
                checkboxes
            }
        }
        .scrollIndicators(.hidden)
    }

    var summary: some View {
        VStack(spacing: 16) {
            SecurityScannerHeaderView(state: verifyViewModel.securityScannerState)

            VStack(spacing: 16) {
                summaryTitle
                summaryFromTo

                if currentTransaction.isLimit {
                    limitTargetPriceRow

                    // A resting `=<` order has no market quote (so the shared
                    // `showGas`/`showFees` fee rows are all suppressed) — surface
                    // the estimated source-chain network fee, the only fee it has.
                    if !currentTransaction.limitNetworkFeeString.isEmpty {
                        separator
                        getNetworkFeeCell(
                            cryptoAmount: currentTransaction.limitNetworkFeeString,
                            fiatAmount: currentTransaction.limitNetworkFeeFiat
                        )
                    }
                }

                if let providerName = currentTransaction.quote?.displayName {
                    separator
                    getValueCell(
                        for: "provider",
                        with: providerName,
                        showIcon: true
                    )
                }

                if currentTransaction.showGas {
                    separator
                    getNetworkFeeCell(
                        cryptoAmount: currentTransaction.swapGasString,
                        fiatAmount: currentTransaction.approveFeeString
                    )
                    .blur(radius: verifyViewModel.isLoadingFees ? 1 : 0)
                }

                if currentTransaction.showFees {
                    separator
                    getValueCell(
                        for: "swapFee",
                        with: currentTransaction.swapFeeString,
                        bracketValue: nil
                    )
                    .blur(radius: verifyViewModel.isLoadingFees ? 1 : 0)
                }

                if currentTransaction.showTotalFees {
                    separator
                    getValueCell(
                        for: "maxTotalFee",
                        with: currentTransaction.totalFeeString
                    )
                    .blur(radius: verifyViewModel.isLoadingFees ? 1 : 0)
                }

                if currentTransaction.advancedSettings.slippage != .auto {
                    separator
                    getValueCell(
                        for: "slippageTolerance",
                        with: currentTransaction.advancedSettings.slippage.displayValue
                    )
                }

                separator
                getValueCell(
                    for: "vault",
                    with: vault.name
                )

                // HIGH security tier: an external recipient is a different
                // destination than the user's own address — it MUST be shown
                // before signing, never applied silently.
                if currentTransaction.hasExternalRecipient {
                    separator
                    getValueCell(
                        for: "recipient",
                        with: currentTransaction.recipientAddress
                    )
                }
            }
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(10)
        }
    }

    /// Row shown only on limit orders, between the from/to summary and the
    /// provider row. Matches Figma 74341:117861:
    /// "Target Price: 1 <toCoin> = <price> <fromCoin>"  ⏱  "<expiry>h"
    @ViewBuilder
    var limitTargetPriceRow: some View {
        if let limit = currentTransaction.limitContext {
            HStack(spacing: 4) {
                // LIM = sourceAmount(fromCoin) × targetPrice, so targetPrice is
                // toCoin-per-1-fromCoin. The row MUST read "1 <fromCoin> = <price>
                // <toCoin>" — passing toCoin first would confirm the reciprocal
                // pair against the signed memo (fund-safety).
                Text(String(
                    format: "limitSwap.verify.targetPrice".localized,
                    currentTransaction.fromCoin.ticker,
                    limit.targetPrice.formatForDisplay(),
                    currentTransaction.toCoin.ticker
                ))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.colors.textSecondary)

                Text("\(limit.expiryHours)h")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        }
    }

    var summaryFromToIcons: some View {
        HStack(spacing: 10) {
            ZStack {
                verticalSeparator
                chevronIcon
            }

            Text("to".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
            separator
        }
    }

    var verticalSeparator: some View {
        Rectangle()
            .frame(width: 1)
            .frame(idealHeight: 80, maxHeight: 100)
            .foregroundStyle(Theme.colors.bgSurface2)
    }

    var summaryFromTo: some View {
        VStack(spacing: 0) {
            getSwapAssetCell(
                for: currentTransaction.fromAmount.formatForDisplay(),
                with: currentTransaction.fromCoin.ticker,
                fiatValue: currentTransaction.fromFiatAmount.formatToFiat(includeCurrencySymbol: true),
                on: currentTransaction.fromCoin.chain,
                coin: currentTransaction.fromCoin,
                isTo: false
            )

            summaryFromToIcons

            getSwapAssetCell(
                for: currentTransaction.toAmountDecimal.formatForDisplay(),
                with: currentTransaction.toCoin.ticker,
                fiatValue: currentTransaction.toFiatAmount.formatToFiat(includeCurrencySymbol: true),
                on: currentTransaction.toCoin.chain,
                coin: currentTransaction.toCoin,
                isTo: true
            )
        }
    }

    var chevronIcon: some View {
        Image(systemName: "arrow.down")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.primaryAccent4)
            .padding(6)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(32)
            .bold()
    }

    var summaryTitle: some View {
        Text(NSLocalizedString(
            currentTransaction.isLimit ? "limitSwap.verify.title" : "youreSwapping",
            comment: ""
        ))
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var checkboxes: some View {
        @Bindable var vm = verifyViewModel
        return VStack(spacing: 16) {
            Checkbox(isChecked: $vm.isAmountCorrect, text: "swapVerifyCheckbox1Description")
            // Limit orders skip the fee/approve checkboxes — there's no
            // market quote to compare against, and limit deposits don't
            // need an ERC20 approve. Figma 74341:117861 shows a single
            // checkbox row.
            if !currentTransaction.isLimit {
                Checkbox(isChecked: $vm.isFeeCorrect, text: "swapVerifyCheckbox2Description")
                if showApproveCheckmark {
                    Checkbox(isChecked: $vm.isApproveCorrect, text: "swapVerifyCheckbox3Description")
                }
            }
        }
    }

    var signButton: some View {
        SigningCTAButtons(
            isFastVault: vault.isFastVault,
            isDisabled: signButtonDisabled,
            singleSignTitle: "signTransaction",
            onFastSign: { fastPasswordPresented = true },
            onPairedSign: {
                fastVaultPassword = .empty
                onSignPress()
            }
        )
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { onSignPress() }
            )
        }
    }

    private func consumePendingRetry() {
        guard let reason = retrySignal.pendingRetryReason else { return }
        retryBannerText = reason.userFacingMessage
        retrySignal.pendingRetryReason = nil
        Task {
            await verifyViewModel.refreshData(
                vault: vault,
                referredCode: referredViewModel.savedReferredCode
            )
        }
    }

    private func onSignPress() {
        let canSign = verifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }

    func signAndMoveToNextView() {
        signButtonDisabled = true
        Task {
            // Fund-safety pre-flight: re-check live inbound (cache-bypassing) for
            // the source chain before building the keysign payload. A confirmed
            // halt sets verifyViewModel.error and aborts without navigating.
            guard await verifyViewModel.isSourceChainSafeToSign() else {
                await MainActor.run { signButtonDisabled = false }
                return
            }
            if let payload = await verifyViewModel.buildSwapKeysignPayload(vault: vault) {
                await MainActor.run {
                    // Fast vaults sign server-side with no peer to pair with,
                    // so route straight into keysign (the bootstrap runs there)
                    // and skip the pairing screen. A present fast password is
                    // the fast-sign signal; an empty one means paired-sign,
                    // which keeps the QR pairing screen.
                    let context = SigningTxContext.swap(
                        vaultPubKeyECDSA: vault.pubKeyECDSA,
                        transaction: currentTransaction,
                        retry: retrySignal
                    )
                    if let fastPassword = fastVaultPassword.nilIfEmpty {
                        router.navigate(to: SigningRoute.keysign(.fast(
                            context: context,
                            keysignPayload: payload,
                            fastVaultPassword: fastPassword
                        )))
                    } else {
                        router.navigate(to: SigningRoute.pair(
                            context: context,
                            keysignPayload: payload,
                            fastVaultPassword: nil
                        ))
                    }
                }
            }
            await MainActor.run { signButtonDisabled = false }
        }
    }

    var showApproveCheckmark: Bool {
        currentTransaction.isApproveRequired
    }

    var separator: some View {
        Separator()
            .opacity(0.2)
    }

    @ViewBuilder
    var refreshCounter: some View {
        // Limit orders execute at a fixed target price, so there is no live quote
        // to refresh — hide the countdown on the limit verify screen.
        if !currentTransaction.isLimit {
            SwapRefreshQuoteCounter(timer: verifyViewModel.timer)
        }
    }

    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        showIcon: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            Text(value)
                .foregroundStyle(Theme.colors.textPrimary)

            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getNetworkFeeCell(
        cryptoAmount: String,
        fiatAmount: String
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("networkFee", comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(cryptoAmount)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)

                Text(fiatAmount)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getSwapAssetCell(
        for amount: String,
        with ticker: String,
        fiatValue: String,
        on chain: Chain? = nil,
        coin: Coin,
        isTo: Bool
    ) -> some View {
        HStack(spacing: 8) {
            getCoinIcon(for: coin)

            VStack(alignment: .leading, spacing: 4) {
                Text("minPayout".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .opacity(isTo ? 1 : 0)
                Group {
                    Text(amount)
                        .foregroundStyle(Theme.colors.textPrimary) +
                    Text(" ") +
                    Text(ticker)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .font(Theme.fonts.bodyLMedium)

                HStack(spacing: 0) {
                    Text(fiatValue)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    if let chain {
                        HStack(spacing: 2) {
                            Spacer()

                            Text(NSLocalizedString("on", comment: ""))
                                .foregroundStyle(Theme.colors.textTertiary)
                                .padding(.trailing, 4)

                            Image(chain.logo)
                                .resizable()
                                .frame(width: 12, height: 12)

                            Text(chain.name)
                                .foregroundStyle(Theme.colors.textPrimary)
                        }
                        .font(Theme.fonts.caption10)
                        .offset(x: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func getCoinIcon(for coin: Coin) -> some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 28, height: 28),
            ticker: coin.ticker,
            tokenChainLogo: nil
        )
        .overlay(
            Circle()
                .stroke(Theme.colors.bgSurface2, lineWidth: 2)
        )
    }
}
