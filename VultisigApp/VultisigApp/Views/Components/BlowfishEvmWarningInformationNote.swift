//
//  BlowfishWarningInformationNote.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import SwiftUI

struct BlowfishWarningInformationNote: View {
    @StateObject var viewModel: BlowfishWarningViewModel
    
    var body: some View {
        Group {
            HStack(spacing: 12) {
                icon
                text
            }
            .padding(12)
            .background(viewModel.backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.borderColor, lineWidth: lineWidth)
            )
        }
    }
    
    var lineWidth: CGFloat {
#if os(iOS)
        1
#elseif os(macOS)
        2
#endif
    }
    
    var icon: some View {
        Image(systemName: viewModel.iconName)
            .foregroundColor(viewModel.iconColor)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.hasWarnings {
                Text(NSLocalizedString("scannedByBlowfish", comment: ""))
                    .foregroundColor(.neutral0)
                    .font(.body12MontserratSemiBold)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(viewModel.warningMessages, id: \.self) { message in
                    Text(message)
                        .foregroundColor(.neutral0)
                        .font(.body12MontserratSemiBold)
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

// You can use this view for both EVM and Solana
typealias BlowfishEvmWarningInformationNote = BlowfishWarningInformationNote
typealias BlowfishSolanaWarningInformationNote = BlowfishWarningInformationNote
