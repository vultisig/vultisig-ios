//
//  SendCryptoVerifySummaryView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI

struct SendCryptoVerifySummaryView<ContentFooter: View>: View {
    let input: SendCryptoVerifySummary
    let contentPadding: CGFloat
    let contentFooter: () -> ContentFooter
    
    init(input: SendCryptoVerifySummary, contentPadding: CGFloat = 0, @ViewBuilder contentFooter: @escaping () -> ContentFooter) {
        self.input = input
        self.contentPadding = contentPadding
        self.contentFooter = contentFooter
    }
    
    var body: some View {
        VStack(spacing: 16) {
            blockAidBanner
            fields
        }
        .padding(.top, 20)
    }
    
    var blockAidBanner: some View {
        Image("blockaidScannedBanner")
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
                contentFooter()
            }
            .padding(.horizontal, contentPadding)
        }
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            summaryTitle
            summaryCoinDetails
            Separator()
            
            Group {
                getValueCell(for: "from", with: input.fromName, bracketValue: input.fromAddress)
                Separator()
            }
            .showIf(input.fromAddress.isNotEmpty)
            
            Group {
                getValueCell(for: "to", with: input.toAddress)
                Separator()
            }
            .showIf(input.toAddress.isNotEmpty)
            
            getValueCell(for: "network", with: input.network, image: input.networkImage)
            Separator()
            
            Group {
                getValueCell(for: "memo", with: input.memo)
                Separator()
            }
            .showIf(input.memo.isNotEmpty)
            
            getValueCell(for: "estNetworkFee", with: input.feeCrypto, secondRowText: input.feeFiat)
        }
        .padding(24)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(LinearGradient.borderGreen, lineWidth: 1)
        )
        .padding(1)
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .foregroundColor(.lightText)
            .font(.body16BrockmannMedium)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var summaryCoinDetails: some View {
        HStack(spacing: 8) {
            Image(input.coinImage)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(32)
            
            Text(input.amount)
                .foregroundColor(.neutral0)
            
            Text(input.coinTicker)
                .foregroundColor(.extraLightGray)
            
            Spacer()
        }
        .font(.body18BrockmannMedium)
    }
    
    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        image: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            if let image {
                Image(image)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundColor(.neutral0)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let secondRowText {
                    Text(secondRowText)
                        .foregroundColor(.extraLightGray)
                }
            }
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            
        }
        .font(.body14BrockmannMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
