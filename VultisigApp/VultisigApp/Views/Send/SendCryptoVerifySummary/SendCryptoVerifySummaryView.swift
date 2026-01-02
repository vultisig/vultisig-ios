//
//  SendCryptoVerifySummaryView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/07/2025.
//

import SwiftUI

struct SendCryptoVerifySummaryView<ContentFooter: View>: View {
    let input: SendCryptoVerifySummary
    @Binding var securityScannerState: SecurityScannerState
    let contentPadding: CGFloat
    let contentFooter: () -> ContentFooter
    
    init(input: SendCryptoVerifySummary, securityScannerState: Binding<SecurityScannerState>, contentPadding: CGFloat = 0) where ContentFooter == EmptyView {
        self.input = input
        self._securityScannerState = securityScannerState
        self.contentPadding = contentPadding
        self.contentFooter = { EmptyView() }
    }
    
    init(input: SendCryptoVerifySummary, securityScannerState: Binding<SecurityScannerState>, contentPadding: CGFloat = 0, @ViewBuilder contentFooter: @escaping () -> ContentFooter) {
        self.input = input
        self._securityScannerState = securityScannerState
        self.contentPadding = contentPadding
        self.contentFooter = contentFooter
    }
    
    var body: some View {
        VStack(spacing: 16) {
            securityScannerHeader
            fields
        }
    }
    
    var securityScannerHeader: some View {
        SecurityScannerHeaderView(state: securityScannerState)
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 30) {
                summary
                contentFooter()
            }
            .padding(.horizontal, contentPadding)
        }
        .padding(.top, 20)
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
            
            if let signature = input.decodedFunctionSignature, !signature.isEmpty {
                getValueCell(for: "functionSignature", with: signature, isMultiLine: true, color: Theme.colors.turquoise)
                Separator()
                
                if let args = input.decodedFunctionArguments, !args.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("functionArguments", comment: ""))
                            .foregroundColor(Theme.colors.textTertiary)
                            .font(Theme.fonts.bodySMedium)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(args)
                                .foregroundColor(Theme.colors.turquoise)
                                .font(Theme.fonts.bodySMedium)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Separator()
                }
            } else {
                Group {
                    getValueCell(for: "memo", with: input.memo, isMultiLine: true)
                    Separator()
                }
                .showIf(input.memo.isNotEmpty)
            }
            
            if let dictionary = input.memoFunctionDictionary, !dictionary.isEmpty {
                ForEach(Array(dictionary.keys), id: \.self) { key in
                    if let value = dictionary[key] {
                        getValueCell(for: key, with: value)
                        Separator()
                    }
                }
            }
            
            getValueCell(for: "network", with: input.network, image: input.networkImage)
            Separator()
            
            getValueCell(for: "estNetworkFee", with: input.feeCrypto, secondRowText: input.feeFiat)
                .blur(radius: input.isCalculatingFee ? 1 : 0)
        }
        .padding(24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(LinearGradient.borderGreen, lineWidth: 1)
        )
        .padding(1)
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .foregroundColor(Theme.colors.textSecondary)
            .font(Theme.fonts.bodyMMedium)
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
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(input.coinTicker)
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
        }
        .font(Theme.fonts.bodyLMedium)
    }
    
    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        secondRowText: String? = nil,
        image: String? = nil,
        isMultiLine: Bool = false,
        color: Color? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
            
            Spacer()
            
            if let image {
                Image(image)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundColor(color ?? Theme.colors.textPrimary)
                    .lineLimit(isMultiLine ? nil : 1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let secondRowText {
                    Text(secondRowText)
                        .foregroundColor(Theme.colors.textTertiary)
                }
            }
            
            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundColor(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
