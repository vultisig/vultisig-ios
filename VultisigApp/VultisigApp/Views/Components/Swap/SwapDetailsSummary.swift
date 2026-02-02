//
//  SwapDetailsSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapDetailsSummary: View {

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel

    @State var showFees: Bool = true

    var body: some View {
        content
            .animation(.easeInOut, value: showFees)
    }

    var content: some View {
        VStack(spacing: 16) {
            if let providerName = tx.quote?.displayName {
                getSummaryCell(
                    leadingText: "provider",
                    trailingText: providerName
                )
            }

            if swapViewModel.showTotalFees(tx: tx) {
                totalFees
            }

            otherFees
        }
        .padding(.top, 8)
    }

    var totalFees: some View {
        Button {
            showFees.toggle()
        } label: {
            totalFeesLabel
        }
    }

    var totalFeesLabel: some View {
        HStack {
            getSummaryCell(
                leadingText: "totalFee",
                trailingText: "\(swapViewModel.totalFeeString(tx: tx))"
            )

            chevron
        }
    }

    var chevron: some View {
        Image(systemName: "chevron.up")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
    }

    var otherFees: some View {
        HStack {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Theme.colors.primaryAccent4)

            expandableFees
        }
        .frame(maxHeight: showFees ? nil : 0)
        .clipped()
    }

    var expandableFees: some View {
        VStack(spacing: 16) {
            if swapViewModel.showGas(tx: tx) {
                swapGas
            }
            
            if !swapViewModel.baseAffiliateFee(tx: tx).isEmpty {
                affiliateFee
            }
            
            if !outboundFeeString.isEmpty {
                outboundFee
            }
            
            if !swapViewModel.vultDiscount(tx: tx).isEmpty {
                vultDiscount
            }
            
            if !swapViewModel.referralDiscount(tx: tx).isEmpty {
                referralDiscount
            }
            
            if !swapViewModel.priceImpactString(tx: tx).isEmpty {
                priceImpact
            }
        }
    }

    var swapGas: some View {
        getSummaryCell(
            leadingText: "networkFee",
            trailingText: "\(swapViewModel.swapGasString(tx: tx)) (\(swapViewModel.approveFeeString(tx: tx)))"
        )
    }
    
    var affiliateFee: some View {
        HStack {
            Text(swapViewModel.swapFeeLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
            
            Text(swapViewModel.baseAffiliateFee(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.caption12)
    }
    
    var vultDiscount: some View {
        HStack {
            Image(systemName: "star.circle") 
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.turquoise)
            
            Text(swapViewModel.vultDiscountLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
            
            Spacer()
            
            Text(swapViewModel.vultDiscount(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }
    
    var outboundFee: some View {
        getSummaryCell(
            leadingText: "Outbound Fee", // Need localizable key ideally, or hardcode for now
            trailingText: outboundFeeString
        )
    }
    
    var referralDiscount: some View {
        HStack {
            Image(systemName: "megaphone")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.turquoise) 
            
            Text(swapViewModel.referralDiscountLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
            
            Spacer()
            
            Text(swapViewModel.referralDiscount(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }
    
    var priceImpact: some View {
        HStack {
            Text("Price Impact")
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
            
            Text(swapViewModel.priceImpactString(tx: tx))
                .foregroundColor(swapViewModel.priceImpactColor(tx: tx))
        }
        .font(Theme.fonts.caption12)
    }

    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(trailingText)
                .foregroundColor(Theme.colors.textSecondary)
                .redacted(reason: swapViewModel.isLoading ? .placeholder : [])
        }
        .font(Theme.fonts.caption12)
    }

    private func getImage(_ image: String) -> some View {
        Image(image)
            .resizable()
            .frame(width: 16, height: 16)
    }

    private func getErrorCell(text: String) -> some View {
        HStack {
            Text(text)
                .foregroundColor(Theme.colors.alertError)
                .font(Theme.fonts.caption12)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)

            Spacer()
        }
    }
    
    private var outboundFeeString: String {
        guard let quote = tx.quote else { return .empty }
        
        var outboundFeeString: String?
        let feeDecimals: Int = 8 // Default to 8 (THORChain standard)
        
        switch quote {
        case .thorchain(let q), .thorchainStagenet(let q), .mayachain(let q):
            outboundFeeString = q.fees.outbound
        default:
            return .empty
        }
        
        guard let outboundFeeString = outboundFeeString,
              let feeAmount = Decimal(string: outboundFeeString) else {
            return .empty
        }
        
        // Fee is in output asset
        let feeCoin = tx.toCoin
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)
        
        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }
}

#Preview {
    ZStack {
        Background()
        SwapDetailsSummary(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel())
    }
}
