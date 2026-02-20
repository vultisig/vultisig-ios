//
//  JoinSwapDoneSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-23.
//

import SwiftUI
import RiveRuntime
import BigInt

struct JoinSwapDoneSummary: View {
    let vault: Vault
    let keysignViewModel: KeysignViewModel
    let summaryViewModel: JoinKeysignSummaryViewModel
    @Binding var showAlert: Bool

    @State var animationVM: RiveViewModel? = nil

    @Environment(\.openURL) var openURL
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            cards
            buttons
        }
        .buttonStyle(BorderlessButtonStyle())
        .onLoad {
            animationVM = RiveViewModel(fileName: "vault_created", autoPlay: true)
        }
    }

    var cards: some View {
        ScrollView {
            VStack {
                animation
                fromToCards
                summary
            }
        }
    }

    var buttons: some View {
        HStack(spacing: 8) {
            trackButton
            doneButton
        }
        .padding(.vertical)
    }

    var trackButton: some View {
        PrimaryButton(title: "track", type: .secondary) {
            if let link = keysignViewModel.getSwapProgressURL(txid: keysignViewModel.txid) {
                progressLink(link: link)
            } else {
                shareLink(txid: keysignViewModel.txid)
            }
        }
    }

    var doneButton: some View {
        PrimaryButton(title: "done") {
            appViewModel.restart()
        }
    }

    var animation: some View {
        ZStack {
            animationVM?.view()
                .frame(width: 280, height: 280)

            animationText
                .offset(y: 50)
        }
    }

    var animationText: some View {
        Text(NSLocalizedString("transactionSuccessful", comment: ""))
            .foregroundStyle(LinearGradient.primaryGradient)
            .font(Theme.fonts.bodyLMedium)
    }

    var fromToCards: some View {
        ZStack {
            HStack(spacing: 8) {
                getFromToCard(
                    coin: summaryViewModel.getFromCoin(keysignViewModel.keysignPayload),
                    title: summaryViewModel.getFromAmount(keysignViewModel.keysignPayload),
                    description: keysignViewModel.keysignPayload?.fromAmountFiatString,
                    isFrom: true
                )

                getFromToCard(
                    coin: summaryViewModel.getToCoin(keysignViewModel.keysignPayload),
                    title: summaryViewModel.getToAmount(keysignViewModel.keysignPayload),
                    description: keysignViewModel.keysignPayload?.toSwapAmountFiatString,
                    isFrom: false
                )
            }

            chevronContent
        }
    }

    var chevronContent: some View {
        ZStack {
            chevronIcon

            filler
                .offset(y: -24)

            filler
                .offset(y: 24)

        }
    }

    var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(Theme.colors.textButtonDisabled)
            .font(Theme.fonts.caption12)
            .bold()
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(60)
            .padding(8)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(60)
            .overlay(
                Circle()
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
    }

    var filler: some View {
        Rectangle()
            .frame(width: 6, height: 18)
            .foregroundColor(Theme.colors.bgPrimary)
    }

    var summary: some View {
        VStack(spacing: 0) {
            getCell(
                title: "txid",
                value: keysignViewModel.txid,
                valueMaxWidth: 120,
                showCopyButton: true
            )

            if let fromAddress = summaryViewModel.getFromCoin(keysignViewModel.keysignPayload)?.address, !fromAddress.isEmpty {
                separator
                getCell(
                    title: "from",
                    value: vault.name,
                    bracketValue: fromAddress,
                    bracketMaxWidth: 120
                )
            }

            if let toAddress = summaryViewModel.getToCoin(keysignViewModel.keysignPayload)?.address, !toAddress.isEmpty {
                separator
                getCell(
                    title: "to",
                    value: toAddress,
                    valueMaxWidth: 120
                )
            }

            separator
            getCell(
                title: "networkFee",
                value: getCalculatedNetworkFee()
            )
        }
        .padding(24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    var separator: some View {
        Separator()
            .opacity(0.2)
    }

    private func getFromToCard(coin: Coin?, title: String, description: String?, isFrom: Bool) -> some View {
        VStack(spacing: 8) {
            Text(isFrom ? "from".localized : "to".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.caption10)

            if let coin {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 32, height: 32),
                    ticker: coin.ticker,
                    tokenChainLogo: coin.tokenChainLogo
                )
                .padding(.bottom, 8)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)

                Text(description?.formatToFiat(includeCurrencySymbol: true) ?? "")
                    .font(Theme.fonts.caption10)
                    .foregroundColor(Theme.colors.textTertiary)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private func getCell(
        title: String,
        value: String?,
        bracketValue: String? = nil,
        valueMaxWidth: CGFloat? = nil,
        bracketMaxWidth: CGFloat? = nil,
        showCopyButton: Bool = false
    ) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(value ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(maxWidth: valueMaxWidth, alignment: .trailing)

            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(Theme.colors.textTertiary)
                .frame(maxWidth: bracketMaxWidth)
                .truncationMode(.middle)
                .lineLimit(1)
            }

            if showCopyButton {
                getCopyButton(for: value)
            }
        }
        .padding(.vertical)
        .font(Theme.fonts.bodySMedium)
    }

    @ViewBuilder
    private func getCopyButton(for value: String?) -> some View {
        Button {
            copy(hash: value)
        } label: {
            Image(systemName: "doc.on.clipboard")
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
        }
    }

    func copy(hash: String?) {
        guard let hash else { return }

        let explorerLink = keysignViewModel.getTransactionExplorerURL(txid: hash)
        showAlert = true
        ClipboardManager.copyToClipboard(explorerLink)
    }

    func getCalculatedNetworkFee() -> String {
        guard let payload = keysignViewModel.keysignPayload else {
            return .zero
        }

        guard let nativeToken = TokensStore.TokenSelectionAssets.first(where: {
            $0.isNativeToken && $0.chain == payload.coin.chain
        }) else {
            return .zero
        }

        if payload.coin.chainType == .EVM {
            let gas = payload.chainSpecific.gas

            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description),
                  let gasDecimal = Decimal(string: gas.description) else {
                return .empty
            }

            let gasGwei = gasDecimal / weiPerGWeiDecimal
            let gasInReadable = gasGwei.formatToDecimal(digits: nativeToken.decimals)

            var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.fee)
            feeInReadable = feeInReadable.nilIfEmpty.map { " (~\($0))" } ?? ""

            return "\(gasInReadable) \(payload.coin.chain.feeUnit)\(feeInReadable)"
        }

        let gasAmount = Decimal(payload.chainSpecific.gas) / pow(10, nativeToken.decimals)
        let gasInReadable = gasAmount.formatToDecimal(digits: nativeToken.decimals)

        var feeInReadable = feesInReadable(coin: payload.coin, fee: payload.chainSpecific.gas)
        feeInReadable = feeInReadable.nilIfEmpty.map { " (~\($0))" } ?? ""

        return "\(gasInReadable) \(nativeToken.ticker)\(feeInReadable)"
    }

    func feesInReadable(coin: Coin, fee: BigInt) -> String {
        var nativeCoinAux: Coin?

        if coin.isNativeToken {
            nativeCoinAux = coin
        } else {
            nativeCoinAux = appViewModel.selectedVault?.coins.first(where: { $0.chain == coin.chain && $0.isNativeToken })
        }

        guard let nativeCoin = nativeCoinAux else {
            return ""
        }

        let feeDecimal = nativeCoin.decimal(for: fee)
        // Use fee-specific formatting with more decimal places (5 instead of 2)
        return RateProvider.shared.fiatFeeString(value: feeDecimal, coin: nativeCoin)
    }

    private func shareLink(txid: String) {
        let urlString = keysignViewModel.getTransactionExplorerURL(txid: txid)
        if !urlString.isEmpty, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func progressLink(link: String) {
        if !link.isEmpty, let url = URL(string: link) {
            openURL(url)
        }
    }
}

#Preview {
    JoinSwapDoneSummary(
        vault: Vault.example,
        keysignViewModel: KeysignViewModel(),
        summaryViewModel: JoinKeysignSummaryViewModel(),
        showAlert: .constant(false)
    )
    .environmentObject(AppViewModel())
}
