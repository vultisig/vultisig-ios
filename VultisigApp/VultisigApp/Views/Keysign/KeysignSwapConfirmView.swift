//
//  KeysignSwapConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.04.2024.
//

import SwiftUI
import BigInt

struct KeysignSwapConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        VStack {
            fields
            button
        }
    }

    var fields: some View {
        VStack {
            Spacer()
            summary
            Spacer()
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            summaryTitle
            summaryFromToContent
            
            separator
            getValueCell(
                for: "provider",
                with: getProvider(),
                showIcon: true
            )
            
            separator
            getValueCell(for: "NetworkFee", with: getCalculatedNetworkFee())
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var button: some View {
        Button(action: {
            self.viewModel.joinKeysignCommittee()
        }) {
            FilledButton(title: "sign")
        }
        .padding(20)
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreBridging", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.lightText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var summaryFromToContent: some View {
        HStack {
            summaryFromToIcons
            summaryFromTo
        }
    }
    
    var summaryFromToIcons: some View {
        VStack(spacing: 0) {
            getCoinIcon(for: viewModel.keysignPayload?.swapPayload?.fromCoin)
            verticalSeparator
            chevronIcon
            verticalSeparator
            getCoinIcon(for: viewModel.keysignPayload?.swapPayload?.toCoin)
        }
    }
    
    var verticalSeparator: some View {
        Rectangle()
            .frame(width: 1, height: 12)
            .foregroundColor(.blue400)
    }
    
    var summaryFromTo: some View {
        VStack(spacing: 16) {
            let payload = viewModel.keysignPayload?.swapPayload
            
            getSwapAssetCell(
                for: getFromAmount(),
                with: payload?.fromCoin.ticker,
                on: payload?.fromCoin.chain
            )
            
            separator
                .padding(.leading, 12)
            
            getSwapAssetCell(
                for: getToAmount(),
                with: viewModel.keysignPayload?.swapPayload?.toCoin.ticker,
                on: viewModel.keysignPayload?.swapPayload?.toCoin.chain
            )
        }
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var chevronIcon: some View {
        Image(systemName: "arrow.down")
            .font(.body12BrockmannMedium)
            .foregroundColor(.persianBlue200)
            .padding(6)
            .background(Color.blue400)
            .cornerRadius(32)
            .bold()
    }

    func getAction() -> String {
        guard viewModel.keysignPayload?.approvePayload == nil else {
            return NSLocalizedString("Approve and Swap", comment: "")
        }
        return NSLocalizedString("Swap", comment: "")
    }

    func getProvider() -> String {
        switch viewModel.keysignPayload?.swapPayload {
        case .oneInch:
            return "1Inch"
        case .thorchain:
            return "THORChain"
        case .mayachain:
            return "Maya protocol"
        case .none:
            return .empty
        }
    }

    var showApprove: Bool {
        viewModel.keysignPayload?.approvePayload != nil
    }

    func getSpender() -> String {
        return viewModel.keysignPayload?.approvePayload?.spender ?? .empty
    }

    func getAmount() -> String {
        guard let fromCoin = viewModel.keysignPayload?.coin, let amount = viewModel.keysignPayload?.approvePayload?.amount else {
            return .empty
        }

        return "\(String(describing: fromCoin.decimal(for: amount)).formatCurrencyWithSeparators()) \(fromCoin.ticker)"
    }

    func getFromAmount() -> String {
        guard let payload = viewModel.keysignPayload?.swapPayload else { return .empty }
        let amount = payload.fromCoin.decimal(for: payload.fromAmount)
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.fromCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.fromCoin.ticker) (\(payload.fromCoin.chain.ticker))"
        }
    }

    func getToAmount() -> String {
        guard let payload = viewModel.keysignPayload?.swapPayload else { return .empty }
        let amount = payload.toAmountDecimal
        if payload.fromCoin.chain == payload.toCoin.chain {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.toCoin.ticker)"
        } else {
            return "\(String(describing: amount).formatCurrencyWithSeparators()) \(payload.toCoin.ticker) (\(payload.toCoin.chain.ticker))"
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
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            Text(value)
                .foregroundColor(.neutral0)
            
            if let bracketValue {
                Text(bracketValue)
                    .foregroundColor(.extraLightGray)
            }
            
        }
        .font(.body14BrockmannMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getSwapAssetCell(
        for amount: String?,
        with ticker: String?,
        on chain: Chain? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Text(amount ?? "")
                    .foregroundColor(.neutral0) +
                Text(" ") +
                Text(ticker ?? "")
                    .foregroundColor(.extraLightGray)
            }
            .font(.body18BrockmannMedium)
            
            if let chain {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("on", comment: ""))
                        .foregroundColor(.extraLightGray)
                        .padding(.trailing, 4)
                    
                    Image(chain.logo)
                        .resizable()
                        .frame(width: 12, height: 12)
                    
                    Text(chain.name)
                        .foregroundColor(.neutral0)
                    
                    Spacer()
                }
                .font(.body10BrockmannMedium)
                .offset(x: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getCoinIcon(for coin: Coin?) -> some View {
        AsyncImageView(
            logo: coin?.logo ?? "",
            size: CGSize(width: 28, height: 28),
            ticker: coin?.ticker ?? "",
            tokenChainLogo: nil
        )
        .overlay(
            Circle()
                .stroke(Color.blue400, lineWidth: 2)
        )
    }
    
    func getCalculatedNetworkFee() -> String {
        guard let payload = viewModel.keysignPayload else {
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

        return "\(gasInReadable) \(payload.coin.chain.feeUnit)\(feeInReadable)"
    }
    
    func feesInReadable(coin: Coin, fee: BigInt) -> String {
        var nativeCoinAux: Coin?
        
        if coin.isNativeToken {
            nativeCoinAux = coin
        } else {
            nativeCoinAux = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == coin.chain && $0.isNativeToken })
        }
        
        
        
        guard let nativeCoin = nativeCoinAux else {
            return ""
        }
        
        let fee = nativeCoin.decimal(for: fee)
        return RateProvider.shared.fiatBalanceString(value: fee, coin: nativeCoin)
    }
}

#Preview {
    KeysignSwapConfirmView(viewModel: JoinKeysignViewModel())
}
